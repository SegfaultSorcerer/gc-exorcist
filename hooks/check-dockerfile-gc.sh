#!/usr/bin/env bash
# check-dockerfile-gc.sh — PreToolUse hook for Write/Edit
# Warns when a Dockerfile contains Java startup without GC configuration flags.
# Always active (no opt-in required).

set -euo pipefail

# The file path being written/edited is passed via TOOL_INPUT env var or as $1
FILE_PATH="${TOOL_INPUT:-${1:-}}"
if [ -z "$FILE_PATH" ]; then
    # Try reading from stdin (some hook implementations pass JSON)
    INPUT="$(cat 2>/dev/null || true)"
    if [ -n "$INPUT" ]; then
        # Try to extract file_path from JSON-like input
        FILE_PATH="$(echo "$INPUT" | grep -oE '"file_path"\s*:\s*"[^"]+"' | head -1 | sed 's/.*"file_path"\s*:\s*"//;s/"$//' || true)"
    fi
fi

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Check if the file is a Dockerfile
BASENAME="$(basename "$FILE_PATH")"
IS_DOCKERFILE=0
case "$BASENAME" in
    Dockerfile|Dockerfile.*|*.dockerfile)
        IS_DOCKERFILE=1
        ;;
esac

if [ "$IS_DOCKERFILE" -eq 0 ]; then
    exit 0
fi

# Read file content if the file exists; for new files, check TOOL_CONTENT or stdin
FILE_CONTENT=""
if [ -f "$FILE_PATH" ]; then
    FILE_CONTENT="$(cat "$FILE_PATH" 2>/dev/null || true)"
fi

# Also check TOOL_CONTENT env var (for Write operations with new content)
if [ -n "${TOOL_CONTENT:-}" ]; then
    FILE_CONTENT="${FILE_CONTENT}${TOOL_CONTENT}"
fi

if [ -z "$FILE_CONTENT" ]; then
    exit 0
fi

# Check if the file contains a java command
HAS_JAVA=0
if echo "$FILE_CONTENT" | grep -qE '(java\s+-jar|java\s+.*-jar|ENTRYPOINT.*java|CMD.*java)'; then
    HAS_JAVA=1
fi

if [ "$HAS_JAVA" -eq 0 ]; then
    exit 0
fi

# Check if GC-related flags are present
HAS_GC_CONFIG=0
if echo "$FILE_CONTENT" | grep -qE '(-XX:MaxRAMPercentage|-Xlog:gc|-XX:\+UseG1GC|-XX:\+UseZGC|-XX:\+UseShenandoahGC|-XX:\+UseParallelGC|-XX:\+PrintGCDetails|-Xloggc|-XX:\+UseConcMarkSweepGC|-XX:InitialRAMPercentage|-XX:MinRAMPercentage)'; then
    HAS_GC_CONFIG=1
fi

if [ "$HAS_GC_CONFIG" -eq 1 ]; then
    exit 0
fi

echo "⚠️ gc-exorcist: Dockerfile contains Java startup without GC configuration. Consider adding: -XX:MaxRAMPercentage=75.0 and GC logging flags. Run /gc-enable for the full configuration."
