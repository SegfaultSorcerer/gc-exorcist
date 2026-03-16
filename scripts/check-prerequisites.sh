#!/usr/bin/env bash
# check-prerequisites.sh — Verify that required and optional tools are available
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

pass=0
warn=0
fail=0

check_tool() {
  local tool="$1"
  local required="$2"

  if command -v "$tool" &>/dev/null; then
    version=$("$tool" -version 2>&1 | head -1 || "$tool" --version 2>&1 | head -1 || echo "unknown")
    printf "${GREEN}[OK]${NC}    %-10s %s\n" "$tool" "$version"
    ((pass++))
  elif [[ "$required" == "true" ]]; then
    printf "${RED}[MISS]${NC}  %-10s (required)\n" "$tool"
    ((fail++))
  else
    printf "${YELLOW}[SKIP]${NC}  %-10s (optional — some features will be unavailable)\n" "$tool"
    ((warn++))
  fi
}

echo "gc-exorcist — prerequisite check"
echo "================================"
echo ""

echo "Required:"
check_tool java true

echo ""
echo "Optional:"
check_tool jcmd false
check_tool awk  false

echo ""
echo "--------------------------------"
printf "Result: ${GREEN}%d passed${NC}, ${YELLOW}%d skipped${NC}, ${RED}%d missing${NC}\n" "$pass" "$warn" "$fail"

if [[ $fail -gt 0 ]]; then
  echo ""
  echo "Install missing required tools before using gc-exorcist."
  exit 1
fi

exit 0
