Lab 1: TPS-Based DoS Protection
================================

This lab configures explicit **transactions-per-second (TPS)** thresholds in
an ASM DoS profile. When a source IP or URL exceeds the threshold, BIG-IP
blocks, challenges, or rate-limits that source until traffic normalizes.
TPS-based protection is the simplest WAF DoS mode — it requires no learning
period and triggers on known numeric thresholds.

.. note::

   This lab must exceed a per-second rate threshold. Ensure the Hackazon container
   is at **full CPU** first — from the Hackazon Web Shell (``10.1.1.5``),
   ``docker update --cpus=0 <hackazon-container>``. A CPU-limited backend caps
   ``ab`` below the threshold so nothing is rejected. See
   :doc:`/setup/lab-topology` (*Backend CPU state*).

Task 1: Verify ASM is Provisioned
-----------------------------------

#. SSH to the BIG-IP::

      ssh admin@10.1.1.11

#. Confirm ASM provisioning level is ``nominal`` or ``dedicated``::

      tmsh show sys provision asm

   Expected output (partial)::

      Sys::Provision
      asm   nominal

   .. important::

      If ASM shows ``none``, navigate to **System > Resource Provisioning**
      in the TMUI and set ASM to **Nominal**. The system will require a reboot.

Task 2: Create the TPS-Based DoS Profile
-----------------------------------------

#. In the TMUI, navigate to **Security > DoS Protection > Protection Profiles**.

#. Click **Create**.

#. Set the **Name** to ``lab-dos-tps``.

#. Under **Application Security**, open **TPS-based Detection** and set
   **Operation Mode** to **Blocking** and **Thresholds Mode** to **Manual**.

#. Under **How to detect attackers and which mitigation to use**, **enable
   By Source IP** — this toggle is required. If it stays off, the thresholds are
   saved but nothing is ever evaluated (a common "why is nothing detected?" trap).
   An IP is treated as an attacker if *either* condition is met:

   .. list-table::
      :header-rows: 1
      :widths: 45 55

      * - Condition
        - Value
      * - Relative Threshold — TPS increased by
        - 500% **and** reached at least 10 TPS
      * - Absolute Threshold — TPS reached
        - 20 TPS

   Under **Select mitigation methods to use on the attacking IP's**, tick
   **Request Blocking → Block All**.

   .. important::

      **Set the absolute threshold below the rate one attack client actually
      reaches on your backend.** A single ``ab`` client through the slow lab
      Hackazon is sampled by the DoS engine at only ~20 TPS, so the default
      absolute threshold of **200** never trips — nothing is detected and the
      event log stays empty. **20** works here; lower it further if your flood
      can't reach it, or raise it on a faster backend. Also, the relative
      **"reached at least"** value must be **≤** the absolute threshold (TMOS
      rejects *min > max*), which is why it is **10** here, not 40.

#. *(CLI equivalent)* the same settings via ``tmsh`` — note the exact 17.5 field
   names, and that **``ip-rate-limiting enabled``** is the "By Source IP" toggle::

      tmsh modify security dos profile lab-dos-tps application modify { lab-dos-tps { \
          tps-based { \
              ip-rate-limiting enabled \
              ip-maximum-tps 20 \
              ip-minimum-tps 10 \
              ip-tps-increase-rate 500 \
              ip-request-blocking-mode block-all } } }
      tmsh save sys config

#. *(Optional)* expand **By URL** and **Site Wide** to set per-URL and
   whole-site criteria — the **By Source IP** tier is enough for this lab.

#. Set the **Prevention Duration** — this controls how mitigation *ramps up* and
   *winds down*:

   .. list-table::
      :header-rows: 1
      :widths: 45 55

      * - Setting
        - Value
      * - Escalation Period
        - 30 seconds
      * - De-escalation Period
        - 60 seconds

   - **Escalation Period** — how long the system stays at each mitigation step
     before moving to the next, more aggressive one. Mitigation is applied in
     steps; if the attack persists past this period, BIG-IP escalates (e.g. from
     a gentler challenge toward outright blocking).
   - **De-escalation Period** — how long the source/URL must stay *below* the
     thresholds before mitigation is relaxed and finally removed. A longer value
     prevents **flapping** (mitigation toggling on/off) when traffic hovers near
     the threshold; too short and a still-active attack resumes the moment
     mitigation lifts (see the stress-based de-escalation question in Lab 4).

#. Leave **Behavioral & Stress-based Detection** disabled for this lab (that is
   Lab 2).

#. Click **Finished**.

Task 3: Attach the DoS Profile and Log Profile to the Virtual Server
--------------------------------------------------------------------

A DoS profile is applied at the **virtual server**, not inside an ASM security
policy — and it needs a **security log profile**, or nothing reaches the event
log and the lab looks like it did nothing.

#. Navigate to **Local Traffic > Virtual Servers**, click **vs-lab-dos**, and open
   the **Security > Policies** tab.

#. Set **DoS Protection Profile** to **Enabled** and select ``lab-dos-tps``.

#. Set **Log Profile** to **Enabled** and move a DoS log profile into
   **Selected** — ``L7-DOS_BOT_Logger`` (or ``ASM-Bot-DoS-Log-All``; both log
   DoS/Bot events). This is what populates *Security > Event Logs > DoS >
   Application Events*.

#. Click **Update**.

   Or via CLI (run the two adds on separate lines — chaining them lets a
   duplicate-profile error abort the log-profile add)::

      tmsh modify ltm virtual vs-lab-dos profiles add { lab-dos-tps }
      tmsh modify ltm virtual vs-lab-dos security-log-profiles add { L7-DOS_BOT_Logger }

#. Confirm both are attached::

      tmsh list ltm virtual vs-lab-dos profiles security-log-profiles

Task 4: Generate Attack Traffic and Observe Blocking
-----------------------------------------------------

#. From the attack client, run a sustained high-rate flood (the backend at full
   CPU — ``docker update --cpus=0`` — lets ``ab`` reach a rate that trips the
   thresholds)::

      ab -n 50000 -c 100 -t 60 -l http://10.1.10.63/

#. While the flood runs, open **Security > Event Logs > DoS > Application Events**
   (and **Security > DoS Protection > DoS Overview** for the live view). Once the
   source-IP rate crosses the threshold, the attack lifecycle appears — three
   event types tied together by one **Attack ID**:

   .. list-table:: DoS L7 event lifecycle
      :header-rows: 1
      :widths: 22 12 66

      * - Event
        - TPS
        - What it means
      * - **Attack started**
        - 20 tps
        - The profile declared a *DOS L7 attack* — the measured source-IP rate
          crossed the detection threshold. Mitigation **Source IP-Based Block
          All** is now in effect for this Attack ID.
      * - **Suspicious entity**
        - 17 tps
        - The per-source attribution. **Entity Type: Source IP / Entity:
          10.1.10.100** names the offender. The columns read **TPS 17 / Detection
          Threshold 20 / Mitigate To 13**, **Threshold Condition: Absolute Manual
          Threshold** — it fired on the absolute ``ip-maximum-tps`` you set (20),
          and rate-limits the entity toward 13. The 20→13 gap is hysteresis that
          prevents flapping.
      * - **Attack ended**
        - 11 tps
        - The rate fell and stayed below the threshold past the **de-escalation
          period** (60 s), so the engine cleared the attack — same Attack ID,
          closing the episode.

   Read it as **detect (started) → identify + throttle the offending entity
   (suspicious entity) → recover when traffic subsides (ended)**, all under one
   Attack ID. "Suspicious entity" is *not* a separate attack — it is the
   per-source decision *within* the attack, which is why only that row carries an
   **Entity**. Unlike the Module 1 iRule labs (whose 429s are ``HTTP::respond`` in
   the data path), these are real ASM DoS-profile events, so they show up here in
   **DoS > Application Events**.

   .. note::

      Each attack episode is one **Attack ID** with an *Attack started* and an
      *Attack ended* row; a second flood makes a second Attack ID. In the default
      list view the **Detection Threshold**, **Mitigate To Threshold**,
      **Threshold Condition**, and **Entity** columns are blank on the
      started/ended rows — those populate on the **Suspicious entity** rows (the
      per-source detail). Click an **Attack ID** to drill into an episode, or widen
      the time filter, to see the suspicious-entity rows and the offending
      **Entity** (e.g. ``10.1.10.100``).

Task 5: Review the DoS Reporting Dashboard
-------------------------------------------

The event log is the per-event record; the **DoS Reporting Dashboard** is the
aggregate rollup of the same attacks — the view you use to brief on an incident.

#. Navigate to **Security > Reporting > DoS > Dashboard** and set the range to
   **Last hour** (top-right filter is **HTTP**).

#. Read the panels for your flood:

   - **DoS Attack IDs** (right rail) — one row per episode (e.g. ``3183025548``)
     with its transaction count, plus a **Not attacked** row for the legitimate /
     under-threshold traffic. This is the clean split between attack and normal.
   - **Attacks** table — one row per attack: **Severity** (Low here — a modest lab
     flood), **Vector: Application**, **Trigger: Source IP Vol.**, the **Virtual
     Server** (``/Common/vs-lab-dos``), **Mitigation: Blocked**, and **Start/End
     Time** (one shows *Ongoing* if a flood is still running).
   - **Virtual Servers Health** — ``vs-lab-dos`` should read **Good** with its
     latency and client-connection counts: proof the mitigation kept the VS
     healthy *during* the attack (the whole point).
   - **Transaction Origins → Sent by Client** — attributes the attack volume to
     the client side.

#. Cross-reference: the **Attack ID** shown here is the same ID as in the event
   log, so you can pivot from the dashboard's aggregate view to the per-event
   detail and back.

Task 6: Review Block Page Behavior
------------------------------------

#. While the flood is running (or immediately after), send a manual request
   from the attack client::

      curl -v http://10.1.10.63/

   The response should be the ASM block page with HTTP **200** (or a
   configured redirect) rather than the application content.

.. note::

   TPS-based blocking applies to the **source IP** for the configured
   blocking duration. Legitimate users from the same IP (e.g., behind a
   shared NAT) will also be blocked during this window. For more granular
   mitigation, consider Behavioral DoS (Lab 2) which targets individual
   bad actors rather than entire IPs.

Questions
~~~~~~~~~

- The ``TPS Increased By 500%`` threshold means blocking triggers when the
  source rate is 5× the **baseline**. What is the baseline, and how is it
  calculated in TPS-based mode?
- How would you configure different thresholds for different URLs
  (e.g., stricter for ``/user/login`` than for ``/``)?
