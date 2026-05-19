## rate-limit-per-ip.tcl
##
## Limits each client IP to THRESHOLD HTTP requests within WINDOW seconds.
## Clients exceeding the limit receive HTTP 429 until the window resets.
##
## Tuning:
##   THRESHOLD  — max requests allowed per window (default: 100)
##   WINDOW     — sliding window in seconds (default: 1)

when RULE_INIT {
    set static::rl_threshold 100
    set static::rl_window    1
}

when HTTP_REQUEST {
    set client [IP::client_addr]
    set key    "rl_ip_[string map {: _} $client]"

    set count [table incr $key]

    if { $count == 1 } {
        table set $key $count $static::rl_window $static::rl_window
    }

    if { $count > $static::rl_threshold } {
        HTTP::respond 429 content "Rate limit exceeded. Try again later." \
            "Content-Type" "text/plain" \
            "Retry-After"  $static::rl_window
        return
    }
}
