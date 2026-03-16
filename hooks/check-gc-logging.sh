#!/usr/bin/env bash
# check-gc-logging.sh — PostToolUse hook for Bash
# Warns when a JVM startup command is missing GC logging flags.
# Only active if .gc-exorcist/warn-no-gc-log.enabled exists in the project root.

set -euo pipefail

# The tool input (command) is passed via TOOL_INPUT env var or stdin.
COMMAND="${TOOL_INPUT:-}"
if [ -z "$COMMAND" ]; then
    COMMAND="$(cat 2>/dev/null || true)"
fi

# Nothing to check if no command was captured
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Check if the command is a JVM startup command
IS_JVM_START=0
case "$COMMAND" in
    *spring-boot:run*|*bootRun*|*"java -jar"*|*"java  -jar"*)
        IS_JVM_START=1
        ;;
esac

if [ "$IS_JVM_START" -eq 0 ]; then
    exit 0
fi

# Check if GC logging flags are already present
HAS_GC_FLAGS=0
case "$COMMAND" in
    *-Xlog:gc*|*-Xlog:*gc*|*-XX:+PrintGCDetails*|*-Xloggc*|*-verbose:gc*)
        HAS_GC_FLAGS=1
        ;;
esac

if [ "$HAS_GC_FLAGS" -eq 1 ]; then
    exit 0
fi

# Only warn if opt-in flag file exists
# Walk up from current directory looking for project root with .gc-exorcist/
PROJECT_ROOT="${PROJECT_DIR:-$(pwd)}"
FLAG_FILE="${PROJECT_ROOT}/.gc-exorcist/warn-no-gc-log.enabled"

if [ ! -f "$FLAG_FILE" ]; then
    exit 0
fi

echo "⚠️ gc-exorcist: No GC logging flags detected in JVM startup command. Run /gc-enable to generate the correct GC logging flags for your JDK version."
