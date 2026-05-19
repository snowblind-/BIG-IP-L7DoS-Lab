## sliding-window-429.tcl
##
## Sliding window rate limiter. Tracks request timestamps per client IP;
## only requests within the last WINDOW seconds count toward the limit.
## Returns HTTP 429 with Retry-After when threshold is exceeded.
##
## Note: More accurate than fixed-window but uses more table memory.
##       Use rate-limit-per-ip.tcl for high-volume, lower-accuracy use cases.
##
## Tuning:
##   THRESHOLD — max requests allowed in any WINDOW-second period (default: 50)
##   WINDOW    — sliding window in seconds (default: 5)

when RULE_INIT {
    set static::sw_threshold 50
    set static::sw_window    5
}

when HTTP_REQUEST {
    set client [IP::client_addr]
    set now    [clock seconds]
    set key    "sw_[string map {: _} $client]"

    # Read existing timestamp list
    set ts_list [table lookup $key]
    if { $ts_list eq "" } { set ts_list {} }

    # Evict timestamps outside the window
    set ts_list [lsearch -all -inline -not $ts_list \
        [lsearch -all -inline $ts_list *]]
    set fresh {}
    foreach ts $ts_list {
        if { $ts >= ($now - $static::sw_window) } {
            lappend fresh $ts
        }
    }
    lappend fresh $now

    # Persist updated list
    table set $key $fresh $static::sw_window [expr { $static::sw_window * 2 }]

    if { [llength $fresh] > $static::sw_threshold } {
        HTTP::respond 429 content "Too many requests." \
            "Content-Type" "text/plain" \
            "Retry-After"  $static::sw_window \
            "X-RateLimit-Limit"     $static::sw_threshold \
            "X-RateLimit-Remaining" "0"
    }
}
