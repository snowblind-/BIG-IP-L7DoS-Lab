#!/usr/bin/env bash
# js-challenge-client.sh
#
# Demonstrate the Bot Defense JavaScript challenge from kali using only
# base-distro tools: firefox-esr (real JS engine) + python3 (stdlib sqlite3).
# No Selenium, no pip, no extra packages.
#
# It contrasts two clients against the same URL:
#   * curl          - no JS engine, cannot solve the challenge (gets mitigated)
#   * firefox-esr   - executes the challenge JS, earns the TS* cookie, passes
#
# Usage:  ./js-challenge-client.sh <url> [wait_secs]
#   e.g.  ./js-challenge-client.sh http://10.1.10.74/ 8
#
set -uo pipefail

URL="${1:-http://10.1.10.74/}"
WAIT="${2:-8}"
OUT="$(mktemp -d)"; PROF="$OUT/prof"; mkdir -p "$PROF"
FF="$(command -v firefox-esr || command -v firefox || true)"

echo "== Target: $URL =="

# 1) curl - no JavaScript
echo; echo "--- curl (no JavaScript) ---"
code="$(curl -s -o "$OUT/curl.html" -w '%{http_code}' -A 'Mozilla/5.0' "$URL" || true)"
echo "HTTP $code, $(wc -c < "$OUT/curl.html") bytes"
if grep -qiE "challenge|please wait|javascript|window\.location|eval\(|bot" "$OUT/curl.html"; then
    echo "curl received the JS CHALLENGE (not the app) - expected for a script."
else
    echo "curl page saved to $OUT/curl.html - inspect it."
fi

# 2) firefox-esr headless - real JS engine
if [ -z "$FF" ]; then
    echo; echo "firefox-esr not found. Base Kali ships it; otherwise use the GUI browser."
    exit 1
fi
echo; echo "--- firefox-esr --headless (executes JavaScript) ---"
"$FF" --headless --new-instance --profile "$PROF" "$URL" >/dev/null 2>&1 &
FFPID=$!
sleep "$WAIT"                                   # let the challenge solve + reload
kill -TERM "$FFPID" 2>/dev/null; sleep 2        # SIGTERM lets Firefox flush cookies

# Cookies the browser earned (python3 stdlib sqlite3 - copy first, DB may be locked)
python3 - "$PROF/cookies.sqlite" <<'PY'
import sqlite3, sys, os, shutil, tempfile
db = sys.argv[1]
if not os.path.exists(db):
    print("  no cookies.sqlite yet - raise the wait_secs argument"); raise SystemExit
tmp = tempfile.mktemp(suffix=".sqlite"); shutil.copy(db, tmp)
try:
    rows = sqlite3.connect(tmp).execute("select name, host from moz_cookies").fetchall()
    if not rows:
        print("  (no cookies - challenge may not have completed; raise the wait)")
    for name, host in rows:
        tag = "  <-- bot-defense token" if name.upper().startswith("TS") else ""
        print(f"  {name}  ({host}){tag}")
finally:
    os.remove(tmp)
PY

# Screenshot what the browser rendered (app vs challenge page)
"$FF" --headless --profile "$PROF" --screenshot "$OUT/browser.png" "$URL" >/dev/null 2>&1 || true

echo
echo "curl page : $OUT/curl.html"
echo "browser   : $OUT/browser.png"
echo
echo "If Firefox earned a TS* cookie and browser.png shows the app, the headless"
echo "browser SOLVED the challenge that curl could not. Do NOT copy the TS cookie"
echo "into curl - the bot-defense cookie is bound to the client that solved it."
