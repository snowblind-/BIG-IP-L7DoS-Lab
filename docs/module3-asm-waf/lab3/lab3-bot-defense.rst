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
   * - DoS-profile VS (Task 1)
     - ``vs-lab-dos`` — ``10.1.10.63``
     - Carries the DoS-profile Proactive Bot Defense
   * - Bot Defense VS (Tasks 2+)
     - ``vs-lab-bot`` — ``10.1.10.74``
     - Carries the standalone profile; the target the tests hit
   * - Backend
     - ``Hackazon_pool`` (member ``10.1.20.20``)
     - Blueprint's existing pool + live Hackazon member

.. note::

   **Run-from key.** Every test/validation below is tagged with where to run it:
   **(kali)** = kali attack client via its UDF **Web Shell** (``curl``);
   **(win-client)** = the Windows client via **superjump Guacamole RDP** (a real
   browser); **(TMUI)** = the BIG-IP GUI, reachable from any browser (win-client
   or superjump). Configuration steps run on the BIG-IP (TMUI or Web Shell).

BIG-IP exposes this in two places, and this lab uses both:

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - Mechanism
     - Capability
   * - DoS profile *Bot Defense*
     - All-or-nothing JS challenge plus bot-signature **category** block/report.
       Simple, bundled with L7 DoS detection. (``bot-defense-profile.json``)
   * - Standalone **Bot Defense profile**
     - Per-class actions, **verify-before vs verify-after** access, per-bot
       **rate limits**, custom signatures, and granular allowlists.
       (``bot-defense-standalone.conf``)

The DoS-profile approach can only *block or report* a category. The per-bot rate
limits, custom signatures, and before/after challenge behaviour this lab
demonstrates require the standalone Bot Defense profile.

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

Task 1: Create the DoS-Profile Bot Defense (baseline)
------------------------------------------------------

*Configuration — run on the BIG-IP (TMUI/CLI).* Build the DoS profile in the
TMUI (its proactive bot defense is far easier to configure in the UI than via
``tmsh``), then attach it by UI or CLI.

#. **Security > DoS Protection > DoS Profiles > Create**. Name it
   ``lab_dos_bot_profile`` and click **Finished**, then open it and select the
   **Application Security** tab. (Section labels vary slightly by TMOS version.)

#. Under **Proactive Bot Defense**, set **Operation Mode** to **Always**
   (proactive, always on), and enable **Block Suspicious Browsers** and the
   **CAPTCHA** challenge.

#. Under **Bot Signatures**, enable bot-signature checking. Set the malicious
   categories — **DOS Tool**, **HTTP Library**, **Network Scanner** — to
   **Block**, and leave **Search Engine**, **Crawler**, and **Site Monitor** on
   **Report**.

#. Attach the profile to ``vs-lab-dos``:

   - **UI:** Local Traffic > Virtual Servers > ``vs-lab-dos`` > **Security >
     Policies**, set **DoS Protection Profile** = ``lab_dos_bot_profile``,
     **Update**.
   - **CLI:** ``tmsh modify ltm virtual vs-lab-dos profiles add { lab_dos_bot_profile }``

#. Confirm the settings (and capture the exact config for CLI reuse)::

      tmsh list security dos profile lab_dos_bot_profile application

.. note::

   ``configs/profiles/bot-defense-profile.json`` is the same profile as an AS3
   declaration — an **instructor** can pre-deploy it instead of clicking through
   (see "Deploying with AS3"). Participants use the UI/CLI steps above.

.. note::

   The lab uses two VIPs so each method is demonstrated in isolation: the DoS
   profile's proactive bot defense on ``vs-lab-dos`` (Task 1) and the standalone
   Bot Defense profile on ``vs-lab-bot`` (Tasks 2+). There is also a hard reason
   to keep them apart **if the DoS profile is deployed via AS3**: AS3 auto-
   generates a shadow ``f5_appsvcs_<dos-profile-name>_botDefense`` profile, which
   then collides with a separate standalone Bot Defense profile on the same VS
   (duplicate-profile error). Building via UI/CLI (Task 1) doesn't create that
   shadow profile, but keeping the split still gives the cleanest demo. See
   :doc:`/setup/lab-topology` for the VIP map.

Task 2: Deploy the Standalone Bot Defense Profile
--------------------------------------------------

*Configuration — run on the BIG-IP.*

#. Copy and merge ``configs/profiles/bot-defense-standalone.conf``::

      tmsh load sys config merge file /var/tmp/bot-defense-standalone.conf

#. Bind it to the lab virtual server::

      tmsh modify ltm virtual vs-lab-bot profiles add { lab-bot-defense }

#. Verify the per-class verification and mitigation actions loaded::

      tmsh list security bot-defense profile lab-bot-defense class-overrides

   You should see ``Browser`` set to ``browser-verify-before-access`` and
   ``Trusted Bot`` set to ``rate-limit`` with ``rate-limit-tps 50``.

Task 3: Demonstrate the Challenge — BEFORE access
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

Task 4: Demonstrate the Challenge — AFTER access
-------------------------------------------------

*Configuration (BIG-IP).* Switch the Browser class to after-access and compare::

   tmsh modify security bot-defense profile lab-bot-defense class-overrides \
       modify { Browser { verification { action browser-verify-after-access-blocking } } }

#. **(kali)** Repeat the ``curl`` from Task 3. This time the **application
   response is returned** with the verification JavaScript injected into it — the
   app *did* see the first request. ``curl`` cannot solve the JS, so the **next**
   request is mitigated.

#. **(TMUI)** Confirm the difference in **Security > Event Logs > Bot Defense >
   Bot Requests**: before-access shows mitigation on the *first* request;
   after-access shows the first request passed and the *second* mitigated.

#. *Configuration (BIG-IP).* Restore the proactive setting when done::

      tmsh modify security bot-defense profile lab-bot-defense class-overrides \
          modify { Browser { verification { action browser-verify-before-access } } }

Task 5: Bot Exceptions by Category and Signature
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

Task 6: Per-Bot Rate Limits
----------------------------

The config caps trusted automation two ways: the ``Trusted Bot`` class at
``rate-limit-tps 50``, and specific signatures (``Googlebot`` 100 TPS,
``bingbot`` 60 TPS) via ``signature-overrides``.

#. **(kali)** Generate sustained traffic above the cap with a permitted
   user-agent::

      for i in $(seq 1 500); do
          curl -so /dev/null \
               -A "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" \
               http://10.1.10.74/ &
      done; wait

#. **(TMUI)** Observe throttling in **Security > Event Logs > Bot Defense** —
   requests above the configured TPS are rate-limited (dropped) while the bot is
   *not* fully blocked. Lower ``rate-limit-tps`` to make the effect obvious.

Task 7: Custom Bot Signature and Policy Exception
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
