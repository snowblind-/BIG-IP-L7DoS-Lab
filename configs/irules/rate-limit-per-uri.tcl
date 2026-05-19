## rate-limit-per-uri.tcl
##
## Applies tighter per-IP rate limits to specific URI prefixes.
## All other URIs are passed through without restriction.
##
## Tuning:
##   protected_uris — list of URI prefixes to protect
##   threshold      — max requests per window for protected URIs
##   window         — window size in seconds

when RULE_INIT {
    set static::uri_threshold 20
    set static::uri_window    1

    # Exact match or prefix match — adjust the [string match] below as needed
    set static::protected_uris {
        "/api/login"
        "/api/register"
        "/search"
        "/checkout"
    }
}

when HTTP_REQUEST {
    set uri    [HTTP::uri]
    set client [IP::client_addr]

    set is_protected 0
    foreach prefix $static::protected_uris {
        if { [string match "${prefix}*" $uri] } {
            set is_protected 1
            break
        }
    }

    if { !$is_protected } { return }

    # Sanitize URI for use as a table key
    set uri_key [string map {/ _ ? _ & _} $uri]
    set key "rl_uri_${client}_${uri_key}"

    set count [table incr $key]
    if { $count == 1 } {
        table set $key $count $static::uri_window $static::uri_window
    }

    if { $count > $static::uri_threshold } {
        HTTP::respond 429 content "Rate limit exceeded for this endpoint." \
            "Content-Type" "text/plain" \
            "Retry-After"  $static::uri_window
    }
}
