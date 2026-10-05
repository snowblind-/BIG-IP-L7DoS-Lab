Lab 3: Proactive Bot Defense
=============================

Proactive Bot Defense injects a JavaScript challenge that legitimate browsers
execute transparently to earn a session cookie. Tools that cannot run
JavaScript — scripts, ``curl``, most bots — never earn the cookie and are
mitigated.

.. list-table:: Lab environment (UDF blueprint)
   :header-rows: 1
   :widths: 28 30 42

   * - Role
     - Address / access
     - Notes
   * - BIG-IP
     - ``10.1.1.11`` (TMUI / Web Shell)
     - 17.1.0.1 (BYOL)
   * - Attack client (kali)
     - ``10.1.10.100`` — Web Shell
     - Runs the ``curl`` tests; no JS engine, so it fails the challenge
   * - Legit client (win-client)
     - ``10.1.10.4`` — Guacamole RDP
     - Real browser — solves the JS challenge and passes
   * - Bot Defense VS
     - ``vs-lab-bot`` — ``10.1.10.74``
     - Carries the standalone Bot Defense profile; the target the tests hit
   * - Backend
     - ``Hackazon_pool`` (member ``10.1.20.20``)
     - Blueprint's existing pool + live Hackazon member

.. note::

   **Run-from key.** Every test/validation below is tagged with where to run it:
   **(kali)** = kali attack client via its UDF **Web Shell** (``curl``);
   **(win-client)** = the Windows client via **superjump Guacamole RDP** (a real
   browser); **(TMUI)** = the BIG-IP GUI, reachable from any browser (win-client
   or superjump). Configuration steps run on the BIG-IP (TMUI or Web Shell).

This lab uses a **standalone Bot Defense profile** (``security bot-defense
profile``) attached to ``vs-lab-bot``. Unlike the bot-signature sub-section bundled
inside a DoS profile — which can only *block or report* a signature category — the
standalone profile provides the full feature set this lab demonstrates:

- per-class actions (Browser / Trusted Bot / Untrusted Bot / Malicious Bot …)
- **verify-before vs. verify-after** access (when the JS challenge is issued)
- per-bot **rate limits**
- custom bot signatures and granular allowlists

(``configs/profiles/bot-defense-standalone.conf`` is the reference config.)

Before vs. After Access Verification
-------------------------------------

The single most important Bot Defense setting is *when* the JavaScript challenge
is issued relative to the application seeing the request.

.. list-table::
   :header-rows: 1
   :widths: 32 38 30

   * - Verification action
     - Behaviour
     - Use when
   * - ``browser-verify-before-access``
     - Challenge served **first**. The origin app never sees the request until
       the browser solves the challenge and presents a valid cookie.
     - Highest protection; login pages, checkout.
   * - ``browser-verify-after-access-blocking``
     - Request is **passed to the app**; JS is injected into the response. If the
       next request fails the challenge it is mitigated.
     - Latency-sensitive paths where a one-request exposure is acceptable.
   * - ``browser-verify-after-access-detection``
     - Same as above but **report-only** — failures are logged, never blocked.
     - Tuning / staging before enforcing.
   * - ``browser-challenge-free-verification``
     - Header inspection only, **no JS challenge**.
     - APIs and clients that cannot run JavaScript.

The cookie flow is the same in every case: solve once, present the cookie on
subsequent requests, and you are not re-challenged for the session.

Task 1: Create the Standalone Bot Defense Profile
--------------------------------------------------

Build the profile in the 17.5 UI so every setting is explicit; the ``tmsh`` merge
in the last note is the instructor fast-path that produces the same result. All
steps are **(TMUI)** unless marked CLI.

#. **General Settings.** Navigate to **Security > Bot Defense > Bot Profiles** and
   click **Create**. Set:

   - **Profile Name:** ``lab-bot-defense``
   - **Enforcement Mode:** **Blocking**
   - **Profile Template:** **Strict** — sets strong defaults you then tune
     (verify-before-access; block untrusted / suspicious / malicious / unknown;
     DoS Attack Mitigation Mode enabled). *Relaxed* (challenge-free) and *Balanced*
     (verify-after-access) are the gentler alternatives.
   - Leave **Signature Staging upon Update** **Disabled**, **Enforcement Readiness
     Period** 7 days, **Redirect to Pool** None, and **Response and Blocking
     Pages** on **Default**.

   .. figure:: /_static/img/lab3/bot-general-settings.png
      :alt: Bot Profile General Settings
      :width: 95%

      General Settings — name, Enforcement Mode = Blocking, Profile Template = Strict.

   **(CLI equivalent)**::

      tmsh create security bot-defense profile lab-bot-defense \
          template strict enforcement-mode blocking \
          description "L7DoS Lab - standalone bot defense"

#. **Bot Mitigation Settings** — the action applied *after* a client is classified.
   With **Strict** the defaults are Trusted=Alarm, Untrusted=Block, Suspicious
   Browser=Block, Malicious=Block, Unknown=Block. Each is a dropdown (**None /
   Alarm / CAPTCHA / Block / Honeypot Page / Redirect to Pool / TCP Reset**). Tune
   two classes so the gentler actions are demonstrated:

   .. list-table::
      :header-rows: 1
      :widths: 26 20 54

      * - Class
        - Action
        - Why
      * - Trusted Bot
        - Alarm
        - Verified good bots (search engines) — log, don't block.
      * - Untrusted Bot
        - CAPTCHA
        - Non-malicious tools/crawlers — challenge rather than hard-block.
      * - Suspicious Browser
        - CAPTCHA
        - Let a real-but-odd browser prove itself.
      * - Malicious Bot
        - Block
        - DoS tools / scanners — block outright.
      * - Unknown
        - Block
        - Unclassified non-browser clients.

   Leave **DoS Attack Mitigation Mode = Enabled** (Strict default): during a DoS
   attack it overrides the per-class actions to Browser=Verify-Before-Access,
   Trusted=Alarm, everything else=Block (it requires a DoS protection profile to be
   enabled).

   .. figure:: /_static/img/lab3/bot-mitigation-settings.png
      :alt: Bot Mitigation Settings per-class actions
      :width: 95%

      Per-class mitigation actions + Strict Mitigation Enforcement Cases.

   **(CLI equivalent)**::

      tmsh modify security bot-defense profile lab-bot-defense class-overrides \
          replace-all-with { \
              "Trusted Bot"       { mitigation { action alarm } } \
              "Untrusted Bot"     { mitigation { action captcha } } \
              "Suspicious Browser"{ mitigation { action captcha } } \
              "Malicious Bot"     { mitigation { action block } } }

#. **Browsers** — when/how the JavaScript challenge is issued:

   - **Browser Access:** **Allow**
   - **Browser Verification:** **Verify Before Access** — proactive: the challenge
     is served first and the app only sees the request after the browser solves it.
     This is the Strict default and the behaviour Tasks 2–3 demonstrate; switch to
     **Verify After Access (Blocking/Detection)** to show the "after" variant.
   - **Device ID Mode:** **Generate Before Access** (Strict default)
   - Leave **Single Page Application** and **Cross Domain Requests** at the template
     defaults unless the app needs them.

   .. figure:: /_static/img/lab3/bot-browsers.png
      :alt: Browsers - Browser Verification before access
      :width: 95%

      Browsers — Browser Verification = Verify Before Access.

#. **Signature Enforcement** — the installed bot signatures (2,600+), grouped by
   **Bot Class** and **Bot Category**, each **Staged** or **Enforced**. Filter by
   category and review: keep **Search Engine** / **Site Monitor** benign; select
   the tooling categories — **HTTP Library**, **DOS Tool**, **Vulnerability
   Scanner** — and click **Enforce** (use **Stage** to observe without blocking for
   the readiness period first).

   .. figure:: /_static/img/lab3/bot-signature-enforcement.png
      :alt: Signature Enforcement list
      :width: 95%

      Signature Enforcement — enforce tooling categories; stage to observe first.

#. **Whitelist** — paths/sources exempt from mitigation and challenges (consulted
   **first**). Click **Create** and add known-safe assets with **Mitigation** and
   **Challenges** both **off**:

   .. list-table::
      :header-rows: 1
      :widths: 22 34 22 22

      * - Source
        - URL
        - Mitigation
        - Challenges
      * - Any
        - ``/favicon.ico``
        - off
        - off
      * - Any
        - ``/health``
        - off
        - off

   Do **not** whitelist the whole client subnet — it contains kali
   (``10.1.10.100``) and would exempt the attacker.

   .. figure:: /_static/img/lab3/bot-whitelist.png
      :alt: Whitelist entries
      :width: 95%

      Whitelist — safe URLs with mitigation and challenges disabled.

#. **Save** the profile, then **bind it** to the virtual server — Local Traffic >
   Virtual Servers > ``vs-lab-bot`` > **Security > Policies**, set **Bot Defense
   Profile** = ``lab-bot-defense`` > **Update**. **(CLI)**::

      tmsh modify ltm virtual vs-lab-bot profiles add { lab-bot-defense }
      tmsh list ltm virtual vs-lab-bot profiles

.. note::

   **Instructor fast-path.** The whole profile is in
   ``configs/profiles/bot-defense-standalone.conf`` — merge it instead of clicking
   through, then bind::

      tmsh load sys config merge file /var/tmp/bot-defense-standalone.conf
      tmsh modify ltm virtual vs-lab-bot profiles add { lab-bot-defense }

   The ``.conf`` also sets per-bot **rate limits** (Trusted Bot 50 TPS, Googlebot
   100, bingbot 60) via ``rate-limit`` actions. The 17.5 **Bot Mitigation** class
   dropdown does not expose a rate-limit-TPS action, so the UI steps use the
   available actions (Alarm/CAPTCHA/Block); the rate-limit values are a CLI-only
   refinement.

.. note::

   **Mitigation precedence** (order BIG-IP consults): Whitelist → DoS Attack
   Mitigation Mode → Microservices → Verified API Access → per-class profile
   mitigation. A whitelisted path is never challenged, and during a DoS attack the
   DoS-mode settings override the per-class actions.

Task 2: Demonstrate the Challenge — BEFORE access
--------------------------------------------------

With ``browser-verify-before-access`` (the value shipped in the config), compare
a script against a real browser:

#. **(kali)** From the kali Web Shell, request the page with ``curl``::

      curl -sv http://10.1.10.74/ 2>&1 | head -40

   Expected: the response body is the **JavaScript challenge**, not the app. The
   origin server never received the request — BIG-IP answered first.

#. **(win-client)** Open ``http://10.1.10.74/`` in a real browser (Guacamole RDP
   to the Windows client). It briefly renders the challenge, runs the JS,
   receives a ``TS<...>`` cookie, and is forwarded to the app in under two
   seconds. Reloading does not re-challenge (cookie is presented).

#. **(win-client)** Inspect the cookie in the browser's **DevTools > Application
   > Cookies** — note the ``TS`` prefixed bot-defense cookie.

This kali-vs-win-client contrast *is* the demonstration: identical request, blocked
for the script, transparent for the browser.

Task 3: Demonstrate the Challenge — AFTER access
-------------------------------------------------

*Configuration (BIG-IP).* Switch the Browser class to after-access and compare::

   tmsh modify security bot-defense profile lab-bot-defense class-overrides \
       modify { Browser { verification { action browser-verify-after-access-blocking } } }

#. **(kali)** Repeat the ``curl`` from Task 2. This time the **application
   response is returned** with the verification JavaScript injected into it — the
   app *did* see the first request. ``curl`` cannot solve the JS, so the **next**
   request is mitigated.

#. **(TMUI)** Confirm the difference in **Security > Event Logs > Bot Defense >
   Bot Requests**: before-access shows mitigation on the *first* request;
   after-access shows the first request passed and the *second* mitigated.

#. *Configuration (BIG-IP).* Restore the proactive setting when done::

      tmsh modify security bot-defense profile lab-bot-defense class-overrides \
          modify { Browser { verification { action browser-verify-before-access } } }

Task 4: Bot Exceptions by Category and Signature
-------------------------------------------------

The standalone profile allows specific bots while blocking others (Search Engine
/ Site Monitor ``none``; Crawler ``alarm``; HTTP Library / DOS Tool ``block``).

#. **(kali)** Send a known search-engine user-agent and confirm it is
   **allowed** (Search Engine category = ``none``)::

      curl -so /dev/null -w "%{http_code}\n" \
           -A "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" \
           http://10.1.10.74/

#. **(kali)** Send an HTTP-library user-agent and confirm it is **blocked**::

      curl -so /dev/null -w "%{http_code}\n" \
           -A "python-requests/2.28.0" \
           http://10.1.10.74/

#. **(TMUI)** Check classification in **Security > Event Logs > Bot Defense >
   Bot Requests** — note the *Bot Signature* and *Bot Category* columns.

Task 5: Per-Bot Rate Limits
----------------------------

Rate limiting caps a *permitted* bot so a verified-but-misbehaving (or
spoofed-then-verified) crawler can't overrun the app. **Rate limit is a CLI-level
action in 17.5** — it is not one of the Bot Mitigation dropdown choices — so apply
it with ``tmsh``.

#. **(BIG-IP)** Set a **low** cap so a single attack client trips it. One
   ``curl``/``ab`` client through the slow lab backend only reaches ~20–30 rps, so
   use **5 TPS** (raise it on a faster backend). Rate-limit the **Trusted Bot**
   class::

      tmsh modify security bot-defense profile lab-bot-defense class-overrides \
          modify { "Trusted Bot" { mitigation { action rate-limit rate-limit-tps 5 } } }

   Or rate-limit a specific signature only (e.g. Googlebot)::

      tmsh modify security bot-defense profile lab-bot-defense signature-overrides \
          replace-all-with { Googlebot { action rate-limit rate-limit-tps 5 } }

#. **(kali)** Generate sustained traffic above the cap with a permitted
   user-agent (Googlebot classifies as a Trusted Bot)::

      for i in $(seq 1 500); do
          curl -so /dev/null \
               -A "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" \
               http://10.1.10.74/ &
      done; wait

#. **(TMUI)** Observe throttling in **Security > Event Logs > Bot Defense** —
   requests above **5 TPS** are rate-limited (dropped) while the bot is *not* fully
   blocked. With the cap this low even a modest ``curl`` loop exceeds it, so the
   effect is obvious. (The default from the ``.conf`` was 50 TPS — too high for one
   lab client to reach.)

Task 6: Custom Bot Signature and Policy Exception
--------------------------------------------------

Beyond the built-in signatures, you can author a **custom bot signature** to
catch a specific tool, then add a **policy exception** so a trusted case that
would otherwise match is let through.

Step 1 — Create the custom signature *(Configuration — BIG-IP)*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. **Security > Bot Defense > Bot Signatures > Bot Signatures List > Create**
   (older builds: **Security > Options > DoS Protection > Bot Signatures List**).

#. Configure:

   .. list-table::
      :header-rows: 1
      :widths: 30 70

      * - Field
        - Value
      * - Name
        - ``lab-scraper``
      * - Category
        - ``DOS Tool`` (a category the profile blocks)
      * - Rule (Simple Edit Mode)
        - **User-agent** → **contains** → ``labscraper``
      * - Risk
        - Medium

   CLI equivalent::

      tmsh create security bot-defense signature lab-scraper \
          category "DOS Tool" risk medium \
          user-agent { match-type contains search-string labscraper }

.. important::

   New custom signatures are placed in **staging** (logged, not blocked) for the
   profile's *Enforcement Readiness Period*. To see it **block** immediately,
   enforce the signature (or set the readiness period to 0) on the profile;
   otherwise the first validation shows the match in the logs while still passing
   traffic.

Step 2 — Validate detection
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. **(kali)** Send the matching user-agent::

      curl -so /dev/null -w "%{http_code}\n" -A "labscraper/1.0" http://10.1.10.74/

   Expected (once enforced): **blocked**. In staging: allowed but logged.

#. **(win-client)** Browse ``http://10.1.10.74/`` normally in the Windows
   client's browser. Expected: **allowed** — a real browser's user-agent does not
   contain ``labscraper``, so the custom signature does not match. (Confirms the
   signature is specific, not blanket.)

#. **(TMUI)** In **Security > Event Logs > Bot Defense > Bot Requests**, confirm
   the kali request matched **Bot Signature = lab-scraper** and the win-client
   request did not.

Step 3 — Add a policy exception *(Configuration — BIG-IP)*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Suppose an internal tool legitimately uses that user-agent. Add a **Signature
Exception** so the policy no longer mitigates ``lab-scraper``:

- **UI:** open the ``lab-bot-defense`` profile > **Signature Exceptions** (or
  *Bot Mitigation Exceptions*) > **Add**, select ``lab-scraper``, action
  **None**, save.
- **CLI:** ::

      tmsh modify security bot-defense profile lab-bot-defense \
          signature-overrides add { lab-scraper { action none } }

Step 4 — Validate the exception
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. **(kali)** Repeat the matching request::

      curl -so /dev/null -w "%{http_code}\n" -A "labscraper/1.0" http://10.1.10.74/

   Expected: **allowed** now — the exception overrides the category block for
   this signature.

#. **(TMUI)** In **Bot Requests**, the same signature now shows action
   **none / allowed** instead of blocked.

#. *Cleanup (BIG-IP), optional* — remove the exception to restore blocking::

      tmsh modify security bot-defense profile lab-bot-defense \
          signature-overrides delete { lab-scraper }

Task 7: Headless browser — solve and detect the JS challenge (from kali)
------------------------------------------------------------------------

Tasks 2–3 contrasted ``curl`` (kali) with a real browser (win-client). You can
show the same *solve vs. fail* entirely from kali using its base-distro
**Firefox ESR** — no GUI, no Selenium, no extra packages — and then see how Bot
Defense classifies an automated browser.

#. **(kali)** Confirm the base tools are present::

      command -v firefox-esr ; python3 --version

#. **(kali)** Run the client against the Bot Defense VS (``vs-lab-bot``)::

      bash /home/ec2-user/lab/scripts/attack/js-challenge-client.sh http://10.1.10.74/ 8

   It fetches once with ``curl`` (no JS → gets the challenge), then drives headless
   Firefox ESR (executes the challenge JS, earns a ``TS*`` cookie), lists the
   cookies it obtained, and screenshots what the browser rendered. If the cookie
   list is empty or the screenshot still shows the challenge, raise the wait
   argument (the JS challenge needs time to solve and reload).

#. **(TMUI)** In **Security > Event Logs > Bot Defense > Bot Requests**, compare
   the two clients: the ``curl`` request is **mitigated** (challenge not solved,
   no cookie), while the headless-Firefox request obtained a cookie and reached
   the app.

**Detection.** Solving the JS challenge only proves the client is *not* a plain
script — it does not make a headless browser "trusted". With **Block Suspicious
Browsers** enabled in the profile and bot-signature checking on, watch whether the
headless Firefox is classified as a clean **Browser** or flagged as a
**Suspicious Browser** / automation in the Bot Requests log. Proactive Bot
Defense combines the JS challenge with browser-integrity and signature checks, so
a JS-capable automation can still be detected even though it passed the challenge.

.. note::

   Whether a solved ``TSPD_101`` cookie can be replayed from another client
   depends on how strictly the deployment binds it (source IP, User-Agent, TLS
   fingerprint) and its TTL. It is **signed and time-stamped**, so it can't be
   forged or altered — but BIG-IP TS/TSPD cookies are often *replayable within
   their lifetime*. The next step shows where that boundary is on this box.

Replay test — cross-source cookie binding *(from kali)*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Solve the challenge once, then replay the earned cookie from the same source and
from a **different** source IP to see whether Bot Defense pins it to the solver.

#. **(kali)** Run the replay test against ``vs-lab-bot``::

      bash /home/ec2-user/lab/scripts/attack/bot-cookie-replay.sh http://10.1.10.74/ 8 10.1.10.200

   It solves with headless Firefox, extracts the ``TSPD_101`` cookie, then
   ``curl``-replays it (a) from kali's primary source and (b) bound to
   ``--interface 10.1.10.200``. Read the verdict it prints:

   - **same PASSED, alt CHALLENGED** → the cookie is **source-IP bound**;
     copying it to another host fails and that host is re-challenged.
   - **both PASSED** → not strictly IP-bound → the cookie is **replayable** to
     other hosts within its TTL (the classic scraper reuse).
   - **both CHALLENGED** → the cookie is also bound to something ``curl`` lacks
     (User-Agent / TLS fingerprint), so even same-host replay is rejected.

#. **(TMUI)** Cross-check in **Security > Event Logs > Bot Defense > Bot
   Requests** — a rejected replay shows as challenged/mitigated, and ASM may log a
   cookie-integrity / hijacking event for the mismatched source.

This is exactly why F5 layers Device ID+, browser-integrity checks, and
Distributed Cloud Bot Defense (whose telemetry is IP/browser-bound with **no**
reusable token) on top of the challenge cookie.

Questions
~~~~~~~~~

- A mobile app using a WebView cannot reliably solve the browser JS challenge.
  Which verification action (or class/allowlist entry) keeps PBD active for
  browsers while letting the app through?
- Your custom ``lab-scraper`` signature matches on user-agent. Give two ways an
  attacker evades it, and which other Module 3 control would still catch each.
- The Signature Exception in Step 3 disables ``lab-scraper`` globally. How would
  you instead except *only* a trusted URL or source IP while still blocking that
  user-agent everywhere else?
- The headless Firefox in Task 7 solved the JS challenge and earned a cookie. Why
  is passing the challenge *not* enough to treat it as a legitimate user, and what
  additional Bot Defense signals still distinguish it from a real browser?
- In the replay test, the same ``TSPD_101`` cookie is sent from kali's primary IP
  and bound to ``10.1.10.200``. What does each outcome — same passes / alt
  challenged, both pass, both challenged — tell you about how the cookie is bound,
  and why does F5 prefer IP/fingerprint binding over a freely replayable token?
