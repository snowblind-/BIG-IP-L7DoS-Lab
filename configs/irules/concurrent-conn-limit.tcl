## concurrent-conn-limit.tcl
##
## Limits simultaneous open connections from a single client IP.
## New connections beyond the limit are reset immediately.
##
## Tuning:
##   MAX_CONNS — max concurrent connections allowed per client IP (default: 20)
##
## The per-IP counter carries a finite idle timeout + absolute lifetime so a
## missed CLIENT_CLOSED (half-open flood, client crash) can't wedge it — a stale
## count self-heals instead of permanently rejecting new connections.

when RULE_INIT {
    set static::max_conns 20
}

when CLIENT_ACCEPTED {
    set client [IP::client_addr]
    set key    "cc_[string map {: _} $client]"

    set conns [table incr $key]
    # Finite TTLs so a missed CLIENT_CLOSED can't wedge the counter.
    table timeout $key 60
    table lifetime $key 300

    if { $conns > $static::max_conns } {
        reject
        return
    }
}

when CLIENT_CLOSED {
    set client [IP::client_addr]
    set key    "cc_[string map {: _} $client]"

    set current [table lookup $key]
    if { $current ne "" && $current > 0 } {
        table set $key [expr { $current - 1 }] 60 300
    }
}
