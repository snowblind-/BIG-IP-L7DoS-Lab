## custom-l7dos-signature.tcl
##
## Custom L7 DoS "signature": detects requests that OMIT the application's
## expected client headers and rate-limits them to a low TPS, while requests
## that carry BOTH required headers pass unrestricted.
##
## Why an iRule and not a native signature:
##   * BIG-IP BOT signatures cannot use negation, so they cannot match on a
##     header being ABSENT (F5: "not allowed in bot signatures: negation").
##   * ATTACK signatures allow negation but can only block/alarm - they cannot
##     rate-limit. So "missing headers -> throttle TPS" is expressed here.
##
## Detection: a legitimate first-party client (the app's SPA / mobile app /
## API caller) always sends REQ_HDR_1 and REQ_HDR_2. Commodity attack tools
## (curl, wrk, generic bots) do not. Missing either header == suspicious.
##
## Mitigation: suspicious sources are capped at SUSPECT_TPS requests per WINDOW
## seconds (per client IP); requests over the cap receive HTTP 429.
##
## Tuning:
##   sig_req_hdr_1 / sig_req_hdr_2 — headers a legitimate client must send
##   sig_suspect_tps               — request cap per window for header-less traffic
##   sig_window                    — window length in seconds

when RULE_INIT {
    set static::sig_req_hdr_1   "X-Client-ID"
    set static::sig_req_hdr_2   "X-Client-Token"
    set static::sig_suspect_tps 5
    set static::sig_window      1
}

when HTTP_REQUEST {
    # --- Signature match: do BOTH required headers exist? ---
    if { [HTTP::header exists $static::sig_req_hdr_1]
      && [HTTP::header exists $static::sig_req_hdr_2] } {
        # Request carries the expected client fingerprint - pass unrestricted.
        return
    }

    # --- Mitigation: throttle header-less (suspicious) traffic per source IP ---
    set client [IP::client_addr]
    set key    "sig_nohdr_[string map {: _} $client]"

    set count [table incr $key]
    if { $count == 1 } {
        # First request of this window - start the countdown timer on the entry.
        table set $key $count $static::sig_window $static::sig_window
    }

    if { $count > $static::sig_suspect_tps } {
        HTTP::respond 429 content "Rate limited: request is missing required client headers." \
            "Content-Type"          "text/plain" \
            "Retry-After"           $static::sig_window \
            "X-L7DoS-Signature"     "missing-client-headers" \
            "X-RateLimit-Limit"     $static::sig_suspect_tps \
            "X-RateLimit-Remaining" "0"
        return
    }
}
