#!/usr/bin/env bash
# gc-capture.sh — Enable or adjust GC logging on a running JVM process without restart
# Usage: ./scripts/gc-capture.sh <command> <PID> [output-dir]
# Commands: enable, disable, status, snapshot
# Requires: jcmd (JDK 9+ for dynamic GC logging)

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Usage ---
usage() {
    echo "Usage: $0 <command> <PID> [output-dir]"
    echo ""
    echo "Commands:"
    echo "  enable  <PID> [output-dir]  Enable GC logging on running JVM (JDK 9+)"
    echo "  disable <PID>               Disable GC logging"
    echo "  status  <PID>               Check current GC logging configuration"
    echo "  snapshot <PID>              Get current GC/heap info without enabling logging"
    echo ""
    echo "Options:"
    echo "  output-dir   Directory for GC log files (default: .gc-exorcist/logs/)"
    exit 1
}

# --- Helpers ---
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

# Check that jcmd is available
check_jcmd() {
    if ! command -v jcmd &>/dev/null; then
        error "jcmd not found. Install a JDK (not just a JRE) and ensure it is on your PATH."
        exit 1
    fi
}

# Validate that PID is a running Java process
validate_pid() {
    local pid="$1"

    if [ -z "$pid" ]; then
        error "PID is required."
        usage
    fi

    # Check PID is numeric
    if ! echo "$pid" | grep -qE '^[0-9]+$'; then
        error "Invalid PID: '$pid' (must be a number)."
        exit 1
    fi

    # Check process exists
    if ! kill -0 "$pid" 2>/dev/null; then
        error "Process $pid not found or permission denied."
        exit 1
    fi

    # Check it's a Java process via jcmd
    if ! jcmd "$pid" VM.version &>/dev/null; then
        error "Process $pid does not appear to be a Java process, or jcmd cannot attach to it."
        error "Ensure the process is a JVM and you have permission to attach (same user or root)."
        exit 1
    fi
}

# Detect JDK version of the target process
detect_jdk_version() {
    local pid="$1"
    local version_output
    version_output=$(jcmd "$pid" VM.version 2>/dev/null || true)

    local major_version
    major_version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)

    if [ -z "$major_version" ]; then
        # Try alternate format: "JDK XX.X.X"
        major_version=$(echo "$version_output" | grep -oE 'JDK [0-9]+' | head -1 | grep -oE '[0-9]+')
    fi

    if [ -z "$major_version" ]; then
        # Fallback: try java -version style in the output
        major_version=$(echo "$version_output" | grep -oE '1\.[0-9]+' | head -1 | cut -d. -f2)
        if [ -n "$major_version" ] && [ "$major_version" -le 8 ]; then
            echo "$major_version"
            return
        fi
    fi

    echo "${major_version:-0}"
}

# --- Commands ---

cmd_enable() {
    local pid="$1"
    local output_dir="${2:-.gc-exorcist/logs}"

    check_jcmd
    validate_pid "$pid"

    local jdk_version
    jdk_version=$(detect_jdk_version "$pid")

    if [ "$jdk_version" -le 8 ] && [ "$jdk_version" -gt 0 ]; then
        error "Dynamic GC logging is not supported on JDK 8 and earlier."
        echo ""
        warn "For JDK 8, add these flags at JVM startup instead:"
        echo "  -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCTimeStamps"
        echo "  -XX:+PrintHeapAtGC -XX:+PrintTenuringDistribution"
        echo "  -Xloggc:${output_dir}/gc.log"
        echo "  -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=5 -XX:GCLogFileSize=20M"
        exit 1
    fi

    # Create output directory
    mkdir -p "$output_dir"

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="${output_dir}/gc_${pid}_${timestamp}.log"

    info "Enabling GC logging for PID $pid"
    info "Output file: $log_file"

    # Enable unified logging for gc (JDK 9+)
    if jcmd "$pid" VM.log output="$log_file" what=gc*=info decorators=time,uptime,level,tags 2>&1; then
        info "GC logging enabled successfully."
        info "Log file: $log_file"
        echo ""
        printf "${CYAN}Tip:${NC} Run '/gc-analyze' on the log file after collecting data.\n"
        printf "${CYAN}Tip:${NC} Run '$0 disable $pid' to stop logging.\n"
    else
        error "Failed to enable GC logging. Check jcmd output above."
        exit 1
    fi
}

cmd_disable() {
    local pid="$1"

    check_jcmd
    validate_pid "$pid"

    info "Disabling GC logging for PID $pid"

    if jcmd "$pid" VM.log disable 2>&1; then
        info "GC logging disabled."
    else
        error "Failed to disable GC logging."
        exit 1
    fi
}

cmd_status() {
    local pid="$1"

    check_jcmd
    validate_pid "$pid"

    info "Current VM.log configuration for PID $pid:"
    echo ""
    jcmd "$pid" VM.log list 2>&1
}

cmd_snapshot() {
    local pid="$1"

    check_jcmd
    validate_pid "$pid"

    printf "${CYAN}=== Heap Info (PID: %s) ===${NC}\n" "$pid"
    jcmd "$pid" GC.heap_info 2>&1 || warn "GC.heap_info not available for this JVM."
    echo ""

    printf "${CYAN}=== VM Flags (PID: %s) ===${NC}\n" "$pid"
    jcmd "$pid" VM.flags 2>&1 || warn "VM.flags not available."
    echo ""

    # Optionally show GC-related flags only
    printf "${CYAN}=== GC-Related Flags ===${NC}\n"
    jcmd "$pid" VM.flags 2>/dev/null | grep -iE '(GC|Heap|Region|RAM|NewSize|OldSize|Metaspace|Survivor)' || echo "  (none matched)"
    echo ""
}

# --- Main ---

if [ $# -lt 1 ]; then
    usage
fi

COMMAND="${1:-}"
PID="${2:-}"

case "$COMMAND" in
    enable)
        if [ -z "$PID" ]; then
            error "PID is required for 'enable'."
            usage
        fi
        cmd_enable "$PID" "${3:-.gc-exorcist/logs}"
        ;;
    disable)
        if [ -z "$PID" ]; then
            error "PID is required for 'disable'."
            usage
        fi
        cmd_disable "$PID"
        ;;
    status)
        if [ -z "$PID" ]; then
            error "PID is required for 'status'."
            usage
        fi
        cmd_status "$PID"
        ;;
    snapshot)
        if [ -z "$PID" ]; then
            error "PID is required for 'snapshot'."
            usage
        fi
        cmd_snapshot "$PID"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        error "Unknown command: '$COMMAND'"
        usage
        ;;
esac
