#!/usr/bin/env bash
# baseline-traffic.sh
#
# Generates realistic baseline HTTP traffic to allow BADoS to learn
# normal traffic patterns before attack simulations begin.
#
# Run for at least 10 minutes before starting Scenario 2.2.

TARGET="${1:-http://10.1.10.100}"
DURATION="${2:-600}"   # seconds (default: 10 min)
CONCURRENCY=5
RPS=20

echo "Generating baseline traffic to $TARGET for ${DURATION}s"
echo "Concurrency: $CONCURRENCY | ~${RPS} req/s"
echo "Press Ctrl+C to stop early."
echo ""

URIS=(
    "/"
    "/index.html"
    "/about"
    "/products"
    "/api/status"
    "/images/logo.png"
    "/css/main.css"
)

end=$(( SECONDS + DURATION ))
count=0

while [ $SECONDS -lt $end ]; do
    uri="${URIS[$((RANDOM % ${#URIS[@]}))]}"
    curl -s -o /dev/null -w "" "${TARGET}${uri}" &

    count=$(( count + 1 ))
    if (( count % CONCURRENCY == 0 )); then
        wait
        sleep $(echo "scale=3; 1/$RPS" | bc)
    fi
done

wait
echo "Baseline complete. $count requests sent."
