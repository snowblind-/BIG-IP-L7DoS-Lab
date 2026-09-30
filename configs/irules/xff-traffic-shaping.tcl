## xff-traffic-shaping.tcl
##
## Lab prep for Behavioral DoS (BADoS) bad-actor detection.
##
## A lab doesn't have dozens of distinct client IPs, so BADoS can't show its key
## behaviour: singling out the bad actor(s) among many legitimate users. This
## iRule synthesises that by inserting an X-Forwarded-For header per request:
##   * good sources  -> a fully random XFF  (looks like many distinct users)
##   * attack sources -> a narrow XFF range (looks like a small repeat-offender
##                       cluster that bad-actor detection can greylist)
##
## REQUIRES: the virtual server's HTTP profile must have "Accept XFF" enabled
## (profile XFF-http), or the DoS profile ignores the injected header and keys on
## the real TCP source. When the source is learned from an L7 header, bad-actor
## mitigation is applied as an HTTP rate-limit rather than a TCP-based one.
##
## Attach to vs-lab-dos for the Module 3 Lab 2 bad-actor demo ONLY, then detach
## it — leaving it on would feed synthetic XFF into the other vs-lab-dos labs.
##
## Tuning (RULE_INIT):
##   xff_good_sources   - real client IPs treated as legitimate (win-client)
##   xff_attack_sources - real client IPs treated as the attacker (kali)
##   xff_attack_prefix  - the /24 the attacker "hides" in
##   xff_attack_hosts   - how many distinct attacker IPs to spread across
##   xff_debug          - 1 to log each good-source XFF to /var/log/ltm

when RULE_INIT {
    set static::xff_good_sources   { 10.1.10.4 }                 ;# win-client
    set static::xff_attack_sources { 10.1.10.100 10.1.10.200 }   ;# kali (.100 primary, .200 secondary)
    set static::xff_attack_prefix  "132.173.99"
    set static::xff_attack_hosts   25
    set static::xff_debug          0
}

when HTTP_REQUEST {
    set src [IP::client_addr]

    # Good traffic -> fully random XFF (simulates many distinct legitimate users)
    if { [lsearch -exact $static::xff_good_sources $src] >= 0 } {
        set xff "[expr {int(rand()*100)}].[expr {int(rand()*100)}].[expr {int(rand()*100)}].[expr {int(rand()*100)}]"
        HTTP::header insert X-Forwarded-For $xff
        if { $static::xff_debug } { log local0.info "xff-shaping good $xff from $src" }
        return
    }

    # Attack traffic -> narrow XFF range (simulates a small repeat-offender cluster)
    if { [lsearch -exact $static::xff_attack_sources $src] >= 0 } {
        set xff "$static::xff_attack_prefix.[expr {int(rand()*$static::xff_attack_hosts)}]"
        HTTP::header insert X-Forwarded-For $xff
    }
}
