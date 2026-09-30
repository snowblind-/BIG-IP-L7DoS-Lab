Lab 2: Behavioral DoS (BADoS)
==============================

Behavioral DoS uses machine learning to build a model of **normal** traffic
patterns, then detects and mitigates anomalies automatically — without requiring
explicit thresholds. This lab walks through the full BADoS lifecycle — baseline
learning, attack detection, and automatic mitigation — and specifically
demonstrates **bad-actor detection**: singling out the offending sources while
legitimate users keep flowing.

.. list-table:: Lab environment
   :header-rows: 1
   :widths: 30 28 42

   * - Role
     - Address
     - Notes
   * - Legitimate users
     - win-client ``10.1.10.4``
     - Runs the baseline script; the iRule gives it a wide, random XFF
   * - Attacker
     - kali ``10.1.10.100``
     - Runs the flood; the iRule gives it a narrow XFF range
   * - Virtual server
     - ``vs-lab-dos`` — ``10.1.10.63``
     - HTTP profile ``XFF-http`` (Accept XFF) + ``xff-traffic-shaping`` iRule
   * - DoS profile
     - ``lab_dos_bados_profile``
     - Behavioral, bad-actor detection enabled (``bados-profile.json``)

Simulating many clients (XFF)
-----------------------------

Bad-actor detection is only meaningful when there are many distinct source IPs
to tell apart — but a lab has only a couple of client hosts. The
``xff-traffic-shaping`` iRule (``configs/irules/xff-traffic-shaping.tcl``) fakes
that diversity by inserting an ``X-Forwarded-For`` header per request: a **wide
random** value for the good source (``10.1.10.4``, looks like many users) and a
**narrow range** (``132.173.99.0/24``) for the attacker (``10.1.10.100`` /
``.200``, looks like a small repeat-offender cluster).

.. important::

   For the DoS profile to key bad-actor detection on the injected header, the
   VS's HTTP profile must have **Accept XFF** enabled — that is the ``XFF-http``
   profile on ``vs-lab-dos`` (created by ``scripts/setup/create-lab-vips.sh``).
   Without it, the header is ignored and detection falls back to the real TCP
   source. When the source is learned from XFF, bad-actor mitigation is applied
   as an **HTTP rate-limit** rather than a TCP-based one.

Prep: enable XFF handling and attach the iRule
----------------------------------------------

Two student steps put ``vs-lab-dos`` into the state this lab needs, then undo them
in Teardown so the other ``vs-lab-dos`` labs are unaffected.

#. Swap ``vs-lab-dos`` to the **XFF-http** profile so the DoS profile trusts the
   injected header (the blueprint ships this Accept-XFF profile):

   - **UI:** Local Traffic > Virtual Servers > ``vs-lab-dos`` > **Properties**,
     set **HTTP Profile (Client)** = ``XFF-http``, **Update**.
   - **CLI:** ``tmsh modify ltm virtual vs-lab-dos profiles delete { http } profiles add { XFF-http }``

#. Create the iRule (**Local Traffic > iRules > Create**, paste
   ``configs/irules/xff-traffic-shaping.tcl``) and attach it:

   - **UI:** ``vs-lab-dos`` > **Resources**, iRules **Manage**, add
     ``xff-traffic-shaping``.
   - **CLI:** ``tmsh modify ltm virtual vs-lab-dos rules { xff-traffic-shaping }``

Task 1: Generate baseline traffic (from win-client)
---------------------------------------------------

#. Connect to **win-client (10.1.10.4)** via superjump Guacamole RDP — the good
   source the iRule recognises.

#. Run the PowerShell baseline generator for at least 10 minutes (pre-staged at
   ``C:\lab\`` — win-client is Windows Server, so it uses the ``.ps1``, not the
   bash ``baseline-traffic.sh``)::

      powershell -ExecutionPolicy Bypass -File C:\lab\baseline-traffic.ps1 -Target http://10.1.10.63/ -DurationSec 600

   Each request is stamped with a different random XFF, so BADoS learns a model
   built from thousands of apparent legitimate clients.

#. Watch learning progress under **Security > DoS Protection > DoS Overview** —
   **Behavioral Analysis Status** moves from **Learning** to **Ready**.

Task 2: Confirm the DoS profile
-------------------------------

#. Create the DoS profile in the TMUI: **Security > DoS Protection > DoS
   Profiles > Create**, name it ``lab_dos_bados_profile``, then open it and
   select the **Application Security** tab. (An instructor may instead pre-deploy
   ``bados-profile.json`` via AS3 — see "Deploying with AS3".)

#. Under **Behavioral & Stress-based Detection > Behavioral Detection and
   Mitigation**, confirm:

   .. list-table::
      :header-rows: 1
      :widths: 50 50

      * - Setting
        - Value
      * - Operation Mode
        - Blocking
      * - Bad actors behavior detection
        - Enabled
      * - Request Blocking Mode
        - Block always

#. Ensure the profile is attached to ``vs-lab-dos`` and TPS-based detection is
   off, to isolate behavioral/bad-actor behaviour.

Task 3: Launch the attack (from kali)
-------------------------------------

#. From **kali (10.1.10.100)** — the source the iRule tags as the attacker —
   run the flood::

      bash ~/lab/scripts/attack/http-flood.sh http://10.1.10.63 60 100

   Every attack request is stamped with an XFF in ``132.173.99.0/24``, so to
   BADoS the flood looks like ~25 repeat offenders rather than one IP.

#. Observe under **Security > DoS Protection > DoS Overview**:

   - **Attack Status: Detected** within 20–30 seconds
   - **Mitigation: Active**
   - The **Bad Actors** table populating with addresses from the
     ``132.173.99.x`` range and their anomaly scores

Task 4: Inspect the mitigation
------------------------------

#. **Security > Event Logs > DoS > Application Events** — entries resemble:

   .. code-block:: text

      [Attack Detected] Behavioral anomaly — request rate deviation 420%
      Mitigated actors: ~25 | Protected URL: /
      Mitigation: HTTP rate-limit applied to 132.173.99.0/24 sources

#. **Security > Reporting > DoS > Dashboard** — the **Bad Actors** panel shows
   the ``132.173.99.x`` cluster; **Server TPS** shows how little reaches the
   pool member once mitigation kicks in.

Task 5: Verify legitimate traffic is preserved
----------------------------------------------

#. While the attack runs, keep the win-client baseline going (or send a request
   that the iRule stamps as a good, random XFF). Those requests continue to
   return **200** — BADoS greylists the narrow attacker cluster, not the broad
   legitimate population.

.. note::

   This is the core BADoS differentiator: it suppresses the specific sources
   driving the anomaly while letting everyone else through. Because the source
   is the XFF value, mitigation is an HTTP-layer rate-limit against the offending
   XFF addresses — TPS-based mode, by contrast, would blanket-block every source
   over the threshold, including innocent shared-NAT users.

Teardown
--------

Undo both prep steps so subsequent ``vs-lab-dos`` labs see real sources on the
plain HTTP profile::

   tmsh modify ltm virtual vs-lab-dos rules none
   tmsh modify ltm virtual vs-lab-dos profiles delete { XFF-http } profiles add { http }
   tmsh save sys config

(Leaving ``XFF-http`` attached is harmless once the iRule is gone — with nothing
injecting XFF, Accept XFF has nothing to act on — but reverting keeps the VS
identical to the other labs.)

Questions
~~~~~~~~~

- BADoS uses a longer De-escalation than Escalation period. Why release a
  greylisted actor slowly rather than immediately?
- The attacker "hides" across a /24 via XFF. How does bad-actor detection still
  catch it, and what would change if the attacker spread across a /16 instead?
- With Accept XFF enabled, what stops a real attacker from simply spoofing an
  XFF header to impersonate a trusted address — and why is trusting XFF only safe
  behind a controlled upstream?
