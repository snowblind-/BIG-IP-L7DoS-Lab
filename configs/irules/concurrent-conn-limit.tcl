## concurrent-conn-limit.tcl
##
## Limits simultaneous open connections from a single client IP.
## New connections beyond the limit are reset immediately.
##
## Tuning:
##   MAX_CONNS — max concurrent connections allowed per client IP (default: 20)

when RULE_INIT {
    set static::max_conns 20
}

when CLIENT_ACCEPTED {
    set client [IP::client_addr]
    set key    "cc_[string map {: _} $client]"

    set conns [table incr $key]
    if { $count == 1 } {
        # No expiry — entry is decremented on CLIENT_CLOSED
        table set $key $conns indefinite indefinite
    }

    if { $conns > $static::max_conns } {
        reject
        return
    }
}

when CLIENT_CLOSED {
    set client [IP::client_addr]
    set key    "cc_[string map {: _} $client]"

    set current [table lookup $key]
    if { $current > 0 } {
        table set $key [expr { $current - 1 }] indefinite indefinite
    }
}
