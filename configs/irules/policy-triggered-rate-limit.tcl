## policy-triggered-rate-limit.tcl
##
## Works with the LTM policy (path-rate-policy.json or datagroup-rate-policy.json).
## The policy classifies each request by inserting X-RateLimit-Profile header;
## this iRule reads that header and enforces the corresponding threshold.
##
## For Scenario 3.3 (datagroup), the policy sets profile "datagroup" and this
## iRule performs a second datagroup lookup to get the actual profile name.
##
## Profiles and their thresholds (req/s per client IP):
##   strict      — 10 req/s   (login, checkout, password reset)
##   medium      — 50 req/s   (search, general API)
##   permissive  — 200 req/s  (static content, home page)
##   datagroup   — resolved at runtime from rate_limit_paths datagroup

when RULE_INIT {
    array set static::rl_thresholds {
        strict      10
        medium      50
        permissive  200
    }
    set static::rl_window 1
}

when HTTP_REQUEST {
    set profile [HTTP::header value "X-RateLimit-Profile"]
    HTTP::header remove "X-RateLimit-Profile"

    if { $profile eq "" } { return }

    # Scenario 3.3: resolve profile from datagroup by URI prefix
    if { $profile eq "datagroup" } {
        set uri [HTTP::uri]
        set profile [class match -value $uri starts_with rate_limit_paths]
        if { $profile eq "" } { return }
    }

    set threshold [lindex [array get static::rl_thresholds $profile] 1]
    if { $threshold eq "" } { return }

    set client [IP::client_addr]
    set key    "rl_policy_${profile}_[string map {: _} $client]"

    set count [table incr $key]
    if { $count == 1 } {
        table set $key $count $static::rl_window $static::rl_window
    }

    if { $count > $threshold } {
        HTTP::respond 429 content "Rate limit exceeded." \
            "Content-Type"          "text/plain" \
            "Retry-After"           $static::rl_window \
            "X-RateLimit-Profile"   $profile \
            "X-RateLimit-Limit"     $threshold \
            "X-RateLimit-Remaining" "0"
    }
}
