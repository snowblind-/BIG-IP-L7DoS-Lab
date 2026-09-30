Instructor Answer Key
=====================

Model answers to the **Questions** at the end of each lab. Instructor material —
keep it out of the student hand-out. Answers are talking points, not the only
correct phrasing; encourage discussion.

Module 1 — iRules
-----------------

Lab 1 — Per-IP rate limiting
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Shared-NAT users (corporate proxy, 100+ employees):** they all share one
source IP, so the per-IP counter sums the whole office. Their combined rate trips
the threshold and legitimate users get blocked — the classic weakness of per-IP
limiting: it can't tell individuals apart behind one address. Fixes: key on an L7
identity (XFF, session cookie, JWT claim) instead of IP, raise/allow-list known
proxy ranges, or move to behavioral/bad-actor detection (Module 3).

**Warning header at 80%:** compare the counter to ``0.8 × threshold``. Between 80%
and 100%, set a flag and add a response header (e.g. ``X-RateLimit-Warning``) in
``HTTP_RESPONSE`` while still forwarding; only ``HTTP::respond 429`` at 100%.

**Why ``table incr``:** it is atomic. A ``lookup`` then ``set`` is a
read-modify-write race — two concurrent requests can both read *N* and both write
*N+1*, undercounting. ``table incr`` increments in one operation, so concurrent
requests are counted correctly (and it's one table op instead of two).

Lab 2 — Per-URI rate limiting
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Query parameters:** depends on the key. Keying on ``[HTTP::uri]`` (includes the
query string) makes ``/search?q=a`` and ``/search?q=b`` *different* buckets — so an
attacker just varies the query to evade the limit. Key on ``[HTTP::path]`` (path
only) so all queries to ``/search`` share one counter.

**Different thresholds per path:** map path → threshold (a ``switch`` on
``HTTP::path`` setting a ``$limit`` variable, or a data-group lookup as in Module
2 Lab 3), then run the generic counter logic against ``$limit``.

Lab 3 — Concurrent connection limit
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**vs. the built-in VS Connection Limit:** the built-in limit is a single global
L4 cap on concurrent connections to the virtual server — blunt, all clients
combined. The iRule tracks concurrent connections *per source IP*, so one abusive
client is capped without touching everyone else, with L7 awareness. Built-in is
faster/simpler; the iRule is granular.

**What it misses:** a high request-*rate* attack that opens and closes
connections quickly (few concurrent at any instant), or many requests over one
reused keep-alive connection. Request-rate limiting handles that — Lab 1 (per-IP)
and Lab 4 (sliding window).

Lab 4 — Sliding window
~~~~~~~~~~~~~~~~~~~~~~~

**Memory upper bound:** the timestamp-list grows with clients × requests-in-window,
so TMM table memory scales badly at internet scale. Apply it to bounded
populations (hundreds to low thousands) or to specific high-value URIs; for large
scale use cheap fixed-window counters (one integer per client) or the DoS
profile's behavioral detection.

**Combine with per-URI:** make the table key a composite of client IP + path
(``sw_<ip>_<path>``) so each (client, endpoint) pair gets its own window, then
apply per-endpoint thresholds.

Lab 5 — Custom L7 DoS signature (header-absence)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Global vs per-IP cap:** change the counter key to a single fixed key so all
header-less traffic shares one ceiling. Per-IP throttles each offender
independently (one bad client can't starve others); global is better when *any*
header-less traffic is inherently suspect, or when attackers spread across many
IPs so per-IP never trips.

**Split detection (LTM policy) from mitigation (iRule):** an LTM policy with an
``http-header ... missing`` condition matches header-less requests and hands them
to ``policy-triggered-rate-limit.tcl`` (via a marker header / rate tier). Gains:
detection is declarative and auditable in the policy, evaluation is efficient, and
one shared mitigation iRule serves many detection rules — separation of "what to
match" from "how to throttle."

**Requiring a token value:** read ``[HTTP::header X-Client-Token]`` and validate
the value (known secret, HMAC, signed/rotating token) rather than just presence.
That crosses from a cheap DoS shape-check into authentication — which needs secret
management, rotation, and replay protection, should fail *closed*, and belongs
with the app/Access, not a fail-open DoS iRule.

Module 2 — LTM Policies
-----------------------

Lab 1 — Rate filter / bandwidth
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**When bandwidth shaping beats request-rate limiting:** when bytes matter more
than request count — large downloads, media/streaming, protecting a
backend/egress link, or when response sizes vary so a few big responses saturate
the link at low request rate. Bandwidth shaping caps bytes/sec; request-rate caps
requests/sec.

**Burst size:** a rate class has a sustained rate plus a burst (bucket depth). Set
the burst to a few seconds' worth of traffic so legitimate bursts (a page pulling
many assets) pass, while sustained traffic is held to the configured rate —
token-bucket style: rate = refill, burst = depth.

Lab 2 — Policy + iRule
~~~~~~~~~~~~~~~~~~~~~~~~

**Why strip ``X-RateLimit-Profile`` before the pool:** it's an internal control
header (policy sets it, iRule reads it to pick a tier). Leaking it exposes policy
internals, and if a client could set it they could spoof
``X-RateLimit-Profile: permissive`` to pick a lax tier. Strip it egress (and
normalize any client-supplied copy on ingress) to protect the control channel.

**No matching rule / missing header:** with no matching rule and no default, the
request passes unmodified (no tier assigned). The iRule must handle a
missing/empty header deliberately — apply a defined default tier (or pass). Decide
the default on purpose: fail-open favors availability; a default tier is safer.
Always handle the empty case so untagged traffic isn't accidentally blocked *or*
accidentally unlimited.

Lab 3 — Data-group driven
~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Overlapping prefixes:** F5 string data-groups are evaluated as a prefix tree, so
``class match -value $uri starts_with rate_limit_paths`` returns the *longest*
matching prefix — ``/api/login`` matches the ``/api/login`` entry rather than
``/api/`` when both exist. If precedence is critical, keep entries non-overlapping
or handle specific-before-general explicitly, and test — don't assume ordering.

**Data-group vs external source:** a data-group is in-memory, fast, and dependency
-free but relatively static (updated via config change/sync). An external source
(runtime iControl REST, sideband) is dynamic and centrally managed but adds
latency, a failure mode, and complexity. Use data-groups for stable lists; use an
external feed for fast-changing/centrally-owned lists — or reconcile the two by
refreshing the data-group from the external source on a schedule.

Lab 4 — Reject bad paths
~~~~~~~~~~~~~~~~~~~~~~~~~~

**TCP reset/drop vs HTTP 403:** a silent drop gives the scanner nothing — no page,
no banner, no confirmation the path exists or that a control is present, and it
burns their time on timeouts. A 403 confirms active filtering (useful recon). For
bait/honeypot paths you want zero information leakage.

**Feed Module 3 Bot Defense:** on a bad-path hit, write the source IP to a shared
address-list / IP-Intelligence category / shun list (via ``table``, a sideband, or
AFM), and have Bot Defense / IP Intelligence block sources in that list — the
honeypot-promotes-to-blocklist pattern.

Module 3 — ASM / Advanced WAF
-----------------------------

Lab 1 — TPS-based
~~~~~~~~~~~~~~~~~

**What the baseline is:** the auto-learned *normal* transactions-per-second for
the URL/source, measured as a moving average over a rolling learning period.
"Increased by 500%" means mitigate when the current rate is 5× that learned
baseline (subject to any absolute floors/ceilings you set) — a relative threshold,
not a fixed number.

**Per-URL thresholds:** in the DoS profile's TPS-based detection, define
URL-specific entries (e.g. ``/api/login``) with stricter TPS/percentage thresholds
than the site-wide default.

Lab 2 — Behavioral DoS (BADoS)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Health recovers mid-attack:** BADoS detected the anomaly, generated dynamic
signatures for the attack traffic, and started mitigating (first global
rate-limiting to protect the server, then targeted signature/bad-actor drops) — so
the server recovers even though the attacker keeps sending, because the bad traffic
is now being dropped. Unlike a static limit (a fixed threshold that blunt-blocks
everyone over it), BADoS learns normal, isolates the anomalous pattern, and
mitigates just that — no preset threshold.

**Dynamic signatures vs bad-actor greylist:** signatures describe the *attack
traffic's shape* and mitigate any request matching the pattern regardless of source
(catches new IPs); the greylist identifies *misbehaving source IPs* and throttles
those sources. You see signatures when the attack has a distinct request pattern
(Request Signatures Detection on); you see greylisting when sources are
identifiable (Bad Actor Detection on). Often both — signatures restore health fast,
bad-actor then pins the sources.

**Persisting a dynamic signature:** gain — it survives the attack, so the same
attack is mitigated instantly next time without re-learning, and it's shareable and
auditable. Risk — a signature born in a noisy, mixed attack may be over-broad and
match legitimate traffic, causing false positives when made always-on. Review its
predicates before persisting; persist only vetted signatures.

Lab 3 — Proactive Bot Defense
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Mobile WebView can't solve the JS challenge:** keep the browser JS challenge on
the Browser class, but handle the app differently — use mobile integrity
verification / the F5 Anti-Bot Mobile SDK for the Mobile class, a
challenge-free/header-based verification for that path, or allowlist the app's API
endpoints or user-agent so PBD skips the JS challenge there while still challenging
browsers.

**Evading the ``lab-scraper`` UA signature:** (1) spoof a real browser user-agent —
the UA-contains signature no longer matches, but behavioral/bad-actor detection or
the rate limits still catch the volumetric behavior; (2) run a headless browser
that solves the JS challenge (or go low-and-slow) — the proactive JS challenge /
verify-before-access catches a non-solving client and rate limits catch the rate.
The custom signature is one narrow layer; the challenge + behavioral + rate-limit
layers cover its gaps.

**Scope the exception to a URL/source:** instead of a global Signature Exception
(action none everywhere), add a **whitelist** entry scoped to the trusted URL or
source IP (``disable-mitigation``) so only that traffic bypasses the signature,
while the signature still blocks the user-agent everywhere else. Whitelist = scoped
bypass; signature exception = global disable.

Lab 4 — Stress-based
~~~~~~~~~~~~~~~~~~~~~

**Legit automated report (200 req/10s):** TPS-based would likely block it — it
exceeds a rate threshold regardless of impact. Stress-based only mitigates when the
*server is actually stressed* (latency climbing), and then targets the heaviest
contributors to that latency. If the server absorbs the report without latency
rising, stress-based leaves it alone — it's more forgiving of harmless bursts.

**De-escalation too short:** if mitigation is released as soon as latency
normalizes — but latency only dropped *because* mitigation was working and the
attack is ongoing — the attack resumes, latency spikes, mitigation re-escalates,
and you get flapping (on/off) with intermittent degradation. A longer
de-escalation confirms the server is genuinely healthy and the attack has actually
stopped before releasing.

Lab 5 — Custom persistent DoS signatures
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Learn Only / Detect Only vs Mitigate:** use them to validate a new signature
without risking false positives — watch what it *would* catch on real traffic
before enforcing. "Use Approved Signatures Only" makes rollout safer: only
manually reviewed/approved signatures actually mitigate, so an auto-generated or
unvetted signature stays inert until you approve it — preventing an over-broad
signature from blocking legit users. Stage → review → approve → Mitigate.

**Keeping only ``http.user_agent_header_exists eq false``:** it matches *every*
request with no User-Agent — far too broad. Many legitimate non-browser clients
omit UA: uptime/health monitors, load-balancer probes, internal scripts, some API
integrations and IoT. You'd generate false positives. (It's also trivially evaded —
an attacker just adds any UA.) That's why the lab ANDs it with ``http.request.method``
and ``http.uri_len`` to pin the actual attack shape.

**Why ``origin`` provenance matters:** when auditing which signatures are
enforcing, ``origin`` says how each came to be — ``dynamic-bdos`` = machine-
generated by BADoS from an observed attack (automatic, possibly broad); ``user-
defined`` = deliberately authored by a person (intentional, with a traceable
rationale/owner). Provenance drives trust and change control: auto-generated
signatures warrant more scrutiny for over-breadth, and user-defined ones have an
owner you can ask when one causes a false positive.
