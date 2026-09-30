Lab 3: Proactive Bot Defense
=============================

Proactive Bot Defense injects a JavaScript challenge that legitimate browsers
execute transparently to earn a session cookie. Tools that cannot run
JavaScript — scripts, ``curl``, most bots — never earn the cookie and are
mitigated.

.. list-table:: Lab environment (UDF blueprint)
   :header-rows: 1
   :widths: 30 30 40

   * - Role
     - Address
     - Notes
   * - BIG-IP (version)
     - 17.1.0.1 (BYOL)
     - Management GUI/SSH at ``10.1.1.11``
   * - Attack client (kali)
     - ``10.1.10.100``
     - Runs all ``curl`` commands in this lab
   * - DoS-profile VS (Task 1)
     - ``vs-lab-dos`` — ``10.1.10.63``
     - Carries the DoS-profile Proactive Bot Defense
   * - Bot Defense VS (Tasks 2–6)
     - ``vs-lab-bot`` — ``10.1.10.74``
     - Carries the standalone profile; the target the ``curl`` demos hit
   * - Backend
     - ``Hackazon_pool``
     - Blueprint's existing pool + live Hackazon member behind the VS

.. note::

   ``10.1.10.100`` is **kali (the attack client)**, not the virtual server —
   every ``curl`` below is issued *from* that host *against* the Hackazon VS.
   The ``curl`` demos target ``vs-lab-bot`` (``10.1.10.74``), which carries the
   standalone Bot Defense profile. Task 1's DoS-profile bot defense lives on a
   separate VS, ``vs-lab-dos`` (``10.1.10.63``) — see the shadow-profile note
   below for why the two are kept apart.

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
       **rate limits**, and granular allowlists. (``bot-defense-standalone.conf``)

The DoS-profile approach can only *block or report* a category. The per-bot
rate limits and the before/after challenge behaviour this lab demonstrates
require the standalone Bot Defense profile.

Before vs. After Access Verification
-------------------------------------

The single most important Bot Defense setting is *when* the JavaScript
challenge is issued relative to the application seeing the request.

.. list-table::
   :header-rows: 1
   :widths: 32 38 30

   * - Verification action
     - Behaviour
     - Use when
   * - ``browser-verify-before-access``
     - Challenge served **first**. The origin app never sees the request until
       the browser solves the challenge and presents a valid cookie.
     - Highest protection; login pages, checkout, anything you never want a
       bot to touch.
   * - ``browser-verify-after-access-blocking``
     - Request is **passed to the app**; the JS is injected into the response.
       If the next request fails the challenge it is mitigated.
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

Build the DoS profile in the TMUI (its proactive bot defense is far easier to
configure in the UI than via ``tmsh``), then attach it by UI or CLI.

#. **Security > DoS Protection > DoS Profiles > Create**. Name it
   ``lab_dos_bot_profile`` and click **Finished**, then open it and select the
   **Application Security** tab. (Section labels vary slightly by TMOS version.)

#. Under **Proactive Bot Defense**, set **Operation Mode** to **Always**
   (proactive, always on), and enable **Block Suspicious Browsers** and the
   **CAPTCHA** challenge.

#. Under **Bot Signatures**, enable bot-signature checking. Set the malicious
   categories — **DOS Tool**, **HTTP Library**, **Network Scanner** — to
   **Block**, and leave **Search Engine**, **Crawler**, and **Site Monitor** on
   **Report** (log but allow legitimate automation).

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

With ``browser-verify-before-access`` (the value shipped in the config):

#. From the attack client, request the page with ``curl``::

      curl -sv http://10.1.10.74/ 2>&1 | head -40

   Expected: the response body is the **JavaScript challenge**, not the app.
   The origin server never received the request — BIG-IP answered first.

#. Open the same URL in a real browser. It briefly renders the challenge, runs
   the JS, receives a ``TS<...>`` cookie, and is forwarded to the app in well
   under two seconds. Re-loading does not re-challenge (cookie is presented).

#. Inspect the cookie in **DevTools > Application > Cookies** — note the ``TS``
   prefixed bot-defense cookie.

Task 4: Demonstrate the Challenge — AFTER access
-------------------------------------------------

Now switch the Browser class to after-access and compare::

   tmsh modify security bot-defense profile lab-bot-defense class-overrides \
       modify { Browser { verification { action browser-verify-after-access-blocking } } }

#. Repeat the ``curl`` from Task 3. This time the **application response is
   returned** with the verification JavaScript injected into it — the app *did*
   see the first request. ``curl`` cannot solve the JS, so the **next** request
   is mitigated.

#. Confirm the difference in **Security > Event Logs > Bot Defense > Bot
   Requests**: before-access shows mitigation on the *first* request;
   after-access shows the first request passed and the *second* mitigated.

#. Restore the proactive setting when done::

      tmsh modify security bot-defense profile lab-bot-defense class-overrides \
          modify { Browser { verification { action browser-verify-before-access } } }

Task 5: Bot Exceptions by Category and Signature
-------------------------------------------------

The standalone profile allows specific bots while blocking others:

.. list-table::
   :header-rows: 1
   :widths: 35 20 45

   * - Bot type
     - Action
     - Rationale
   * - Search Engine (category)
     - ``none``
     - Allow verified Google/Bing indexing.
   * - Site Monitor (category)
     - ``none``
     - Allow uptime/health monitors.
   * - Crawler (category)
     - ``alarm``
     - Log generic crawlers without blocking.
   * - HTTP Library / DOS Tool (category)
     - ``block``
     - ``curl``, ``python-requests``, attack tooling.

#. Send a known search-engine user-agent and confirm it is **allowed**
   (action ``none`` for the Search Engine category)::

      curl -so /dev/null -w "%{http_code}\n" \
           -A "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" \
           http://10.1.10.74/

#. Send an HTTP-library user-agent and confirm it is **blocked**::

      curl -so /dev/null -w "%{http_code}\n" \
           -A "python-requests/2.28.0" \
           http://10.1.10.74/

#. Check classification in **Security > Event Logs > Bot Defense > Bot
   Requests** — note the *Bot Signature* and *Bot Category* columns.

Task 6: Per-Bot Rate Limits
----------------------------

Allowing a bot is not the same as letting it run unbounded. The config caps
trusted automation two ways:

- **Class level** — the ``Trusted Bot`` class uses ``rate-limit`` /
  ``rate-limit-tps 50``: any verified good bot is throttled past 50 TPS.
- **Signature level** — ``Googlebot`` is capped at 100 TPS and ``bingbot`` at
  60 TPS via ``signature-overrides``.

#. Generate sustained traffic above the cap with a permitted user-agent::

      for i in $(seq 1 500); do
          curl -so /dev/null \
               -A "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" \
               http://10.1.10.74/ &
      done; wait

#. Observe throttling in **Security > Event Logs > Bot Defense** — requests
   above the configured TPS are rate-limited (dropped) while the bot is *not*
   fully blocked. Lower ``rate-limit-tps`` to make the effect obvious in a
   small lab.

.. important::

   ``rate-limit`` is only valid for **classes and signatures**, and
   ``rate-limit-tps`` is only honoured when the action is ``rate-limit``.
   Signature names are environment-specific; list what is installed with
   ``tmsh list security bot-defense signature`` before referencing one.

Questions
~~~~~~~~~

- A mobile app using a WebView cannot reliably solve the browser JS challenge.
  Which verification action (or which class/allowlist entry) keeps PBD active
  for browsers while letting the app through?
- Before-access verification adds a challenge round-trip to the *first* request
  of every session. For a high-traffic API behind a SPA, what combination of
  ``single-page-application``, ``deviceid-mode``, and verification action
  minimises that latency while still classifying clients?
- You allow the Search Engine category but cap Trusted Bots at 50 TPS. What
  happens to a spoofed user-agent claiming to be Googlebot that fails reverse
  DNS / signature verification?
