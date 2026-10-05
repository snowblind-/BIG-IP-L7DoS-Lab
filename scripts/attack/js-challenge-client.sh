#!/usr/bin/env bash
# js-challenge-client.sh
#
# Show how Bot Defense treats NON-BROWSER automation vs. a real browser.
#
# This lab image cannot run a modern browser from kali (Firefox ESR 45 has no
# --headless; a 2025 Chrome needs a newer glibc/NSS than the image provides), so
# this script drives HTTP clients only (Part A). Run the real-browser half
# manually from superjump (Lab 5, Task 7 Part B).
#
# Part A, from kali:
#   * curl with no JS engine      -> receives the JS CHALLENGE page, never the app
#   * three client identities     -> each classified/mitigated differently:
#       bare "Mozilla/5.0"        -> Malicious Bot / Exploit Tool (sparse UA = tool)
#       "labclient/1.0"           -> Unknown (rate-limited if Unknown = Rate Limit)
#       Googlebot UA              -> Trusted Bot (if FCrDNS-verified) or
#                                    Malicious Bot / Search Engine Verification Failed
#
# Usage:  ./js-challenge-client.sh [url]
#   e.g.  ./js-challenge-client.sh http://10.1.10.74/

set -uo pipefail
URL="${1:-http://10.1.10.74/}"
OUT="$(mktemp -d)"
echo "== Target: $URL =="

# 1) curl, no JavaScript -> gets the challenge page, not the app
echo; echo "--- curl (no JavaScript engine) ---"
code="$(curl -s -o "$OUT/curl.html" -w '%{http_code}' -A 'Mozilla/5.0' "$URL" || true)"
echo "HTTP $code, $(wc -c < "$OUT/curl.html") bytes  (saved: $OUT/curl.html)"
if grep -qiE "challenge|please wait|javascript|window\.location|eval\(|bot" "$OUT/curl.html"; then
    echo "-> curl received the JS CHALLENGE page, not the app. A script cannot solve it."
else
    echo "-> inspect $OUT/curl.html to see what came back."
fi
echo "   (head of the returned page:)"
sed -n '1,12p' "$OUT/curl.html" | sed 's/^/     /'

# 2) client-identity personas -> classification differs by who you claim to be
echo; echo "--- client identity personas (then read Bot Requests for each) ---"
run() { # $1 label  $2 ua  [extra curl args...]
    local label="$1" ua="$2"; shift 2
    local c; c="$(curl -s -o /dev/null -w '%{http_code}' -A "$ua" "$@" "$URL" || true)"
    printf '  %-20s HTTP %s\n' "$label" "$c"
}
run "bare Mozilla/5.0" "Mozilla/5.0"
run "neutral tool UA"  "labclient/1.0"
run "Googlebot (UA)"   "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"

cat <<'EOF'

Open Security > Event Logs > Bot Defense > Bot Requests and note Bot Class /
Mitigation Action for each source:
  bare Mozilla/5.0  -> Malicious Bot / Exploit Tool  (blocked)
  labclient/1.0     -> Unknown  (rate-limited if Unknown = Rate Limit, Task 5)
  Googlebot UA      -> Trusted Bot (if the source PTR verifies) OR
                       Malicious Bot / Search Engine Verification Failed (masquerade)

None of these solve the JS challenge -- a script has no JS engine. Run the
real-browser half manually from superjump (ACCESS > FIREFOX -> this URL) and watch
the Browser-verified entry appear (Lab 5, Task 7 Part B).
EOF

# ---------------------------------------------------------------------------
# OPTIONAL (future / upgraded image): scripted headless solve with a MODERN
# browser. Intentionally skipped here -- the lab image's glibc/NSS are too old to
# run a current Chrome, and Firefox ESR 45 has no headless mode. If a usable
# Chrome/Chromium is ever present, this block drives it and screenshots the result
# (app = solved; challenge = failed). Even when it SOLVES the challenge, a headless
# browser leaks automation signals (navigator.webdriver, etc.) and may still log as
# a Suspicious Browser -- which is the "solved but still detected" demo.
#
#   CHROME="$(command -v chromium || command -v google-chrome || echo /tmp/chrome-linux64/chrome)"
#   if "$CHROME" --version >/dev/null 2>&1; then
#       mkdir -p "$OUT/cprof"
#       "$CHROME" --headless=new --no-sandbox --disable-gpu \
#           --user-data-dir="$OUT/cprof" --virtual-time-budget=12000 \
#           --screenshot="$OUT/browser.png" "$URL" >/dev/null 2>&1 || true
#       echo "headless screenshot: $OUT/browser.png"
#   fi
#
# To fetch a modern Chrome on an upgraded image (needs internet):
#   U=$(curl -s https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json \
#       | tr ',' '\n' | grep -o 'https://[^"]*linux64/chrome-linux64.zip' | head -1)
#   curl -L -o /tmp/chrome.zip "$U" && unzip -q /tmp/chrome.zip -d /tmp/
# ---------------------------------------------------------------------------
