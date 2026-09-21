Lab 5: Custom L7 DoS Signature — Header-Absence Rate Limiting
=============================================================

This lab builds a **custom L7 DoS signature** that separates legitimate traffic
from an attack by a property of the request itself, then mitigates the attack by
rate-limiting the offenders to a low TPS.

The signature logic is deliberately simple and effective: a legitimate
first-party client (the app's single-page front end, mobile app, or API caller)
always sends two application-specific headers. Commodity attack tooling — ``curl``,
``wrk``, ``ab``, generic bots — does not. **If either required header is
missing, the request is throttled to a low request rate; if both are present, it
passes untouched.**

.. list-table:: Lab environment
   :header-rows: 1
   :widths: 35 30 35

   * - Role
     - Address
     - Notes
   * - Attack client (kali)
     - ``10.1.10.100``
     - Sends requests WITHOUT the required headers
   * - Virtual server
     - ``10.1.10.61``
     - iRule attached here
   * - Required header 1
     - ``X-Client-ID``
     - Sent by legitimate clients
   * - Required header 2
     - ``X-Client-Token``
     - Sent by legitimate clients

Why an iRule and not a bot signature
-------------------------------------

You might expect to build this as a custom *bot signature* in Bot Defense. You
cannot, because of two BIG-IP constraints:

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - Signature type
     - Limitation
   * - Bot signature
     - **Negation is not permitted.** A bot signature can only match content
       that is *present* (user-agent, ``headercontent``, ``uricontent``) — it
       cannot match on a header being *absent*.
   * - Attack signature
     - Negation *is* allowed, but the only actions are **block / alarm**. Attack
       signatures cannot rate-limit.

"Header absent → rate-limit TPS" needs both negation and a rate-limit action, so
it is implemented as an iRule. iRules run in TMM, need no ASM license, and can
match on any combination of IP, URI, headers, or cookies — see the Module 1
overview.

.. note::

   The inverse — matching a header/user-agent that *is* present and rate-limiting
   it — *can* be done natively: write a positive-match custom bot signature,
   assign it to a category, and set that category's action to ``rate-limit`` with
   ``rate-limit-tps`` (see Module 3, Lab 3). Use that when you can enumerate the
   bad clients; use this iRule when you can only enumerate the *good* ones.

Task 1: Review the signature logic
-----------------------------------

Open ``configs/irules/custom-l7dos-signature.tcl``. The ``RULE_INIT`` block
defines the two required headers and the throttle:

.. code-block:: tcl

   set static::sig_req_hdr_1   "X-Client-ID"
   set static::sig_req_hdr_2   "X-Client-Token"
   set static::sig_suspect_tps 5
   set static::sig_window      1

On each request the iRule passes traffic that carries **both** headers, and
applies a per-source-IP fixed-window counter (5 requests / second by default) to
everything else, returning ``429`` past the cap.

Task 2: Deploy and attach the iRule
------------------------------------

#. Create the iRule on the BIG-IP::

      tmsh create ltm rule custom-l7dos-signature

   Paste the contents of ``custom-l7dos-signature.tcl`` (or merge it from a
   file), then save.

#. Attach it to the lab virtual server::

      tmsh modify ltm virtual vs-lab-irules rules { custom-l7dos-signature }

   If other Module 1 rules are attached, ordering does not matter here — this
   rule returns early for legitimate traffic and responds directly for throttled
   traffic.

Task 3: Baseline — legitimate client (headers present)
-------------------------------------------------------

From kali (``10.1.10.100``), send a fast burst that includes both headers::

   for i in $(seq 1 30); do
       curl -s -o /dev/null -w "%{http_code}\n" \
            -H "X-Client-ID: web-portal" \
            -H "X-Client-Token: s3cr3t-demo" \
            http://10.1.10.61/
   done

Expected result: **every request returns 200**. Well-formed clients are never
throttled, regardless of rate — the signature did not match them.

Task 4: Simulate the attack (headers absent)
---------------------------------------------

Now send the same burst *without* the headers — this is what commodity tooling
looks like::

   for i in $(seq 1 30); do
       curl -s -o /dev/null -w "%{http_code}\n" http://10.1.10.61/
   done

Expected result: the first **5** requests return ``200``, then the rest return
``429`` until the 1-second window rolls over. Inspect the mitigation headers on a
blocked response::

   curl -sD - -o /dev/null http://10.1.10.61/ \
        http://10.1.10.61/ http://10.1.10.61/ http://10.1.10.61/ \
        http://10.1.10.61/ http://10.1.10.61/ | grep -i "X-L7DoS\|X-RateLimit\|HTTP/"

You should see ``X-L7DoS-Signature: missing-client-headers`` and
``X-RateLimit-Limit: 5`` on the throttled responses.

You can also drive the existing flood script (which does **not** send the
headers) and watch it collapse to the cap::

   bash ~/lab/scripts/attack/http-flood.sh http://10.1.10.61 30 50

Task 5: Demonstrate effectiveness under load
---------------------------------------------

Run the two side by side to make the contrast obvious:

#. Attacker flood without headers — throttled to ~5 rps, the origin pool sees
   almost none of it (TMM answers with ``429`` before the pool is touched).

#. Legitimate client with headers, in parallel — continues to receive ``200``
   at full speed because its requests never match the signature.

This is the core value: the mitigation targets the *attack's* shape, so a flood
is neutralized while real users are unaffected — no CAPTCHA, no JS challenge, no
IP blocklist to maintain.

.. important::

   The two headers are a **shared secret of convenience, not authentication** —
   an attacker who learns them can add them and bypass the signature. Use this to
   shed unsophisticated floods cheaply, and layer it with Bot Defense (Module 3)
   or behavioral detection for adaptive adversaries. For anything sensitive,
   validate a signed/rotating token value, not merely the header's presence.

Questions
~~~~~~~~~

- The signature keys the counter on client IP. How would you change it to a
  single global cap for *all* header-less traffic, and when is each better?
- How could you split detection from mitigation using an LTM policy
  (``http-header ... missing`` condition) feeding the Module 2
  ``policy-triggered-rate-limit.tcl`` iRule? What do you gain?
- The current check only tests header *presence*. Sketch the change to also
  require a valid token *value* in ``X-Client-Token`` — and note why that moves
  the logic closer to authentication than DoS mitigation.
