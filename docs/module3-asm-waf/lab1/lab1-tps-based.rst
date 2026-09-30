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

#. Under **How to detect attackers and which mitigation to use**, expand
   **By Source IP**. An IP is treated as an attacker if *either* condition is met:

   .. list-table::
      :header-rows: 1
      :widths: 45 55

      * - Condition
        - Value
      * - Relative Threshold — TPS increased by
        - 500% **and** reached at least 40 TPS
      * - Absolute Threshold — TPS reached
        - 200 TPS

   Under **Select mitigation methods to use on the attacking IP's**, tick
   **Request Blocking → Block All** (start with blocking so the effect is
   obvious; Client-Side Integrity Defense and CAPTCHA are gentler steps you can
   add later).

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

Task 3: Attach the Profile to the Security Policy
--------------------------------------------------

#. Navigate to **Security > Application Security > Security Policies**.

#. Click **lab-policy**.

#. Under **DoS Protection**, select ``lab-dos-tps``.

#. Click **Save** and then **Apply Policy**.

Task 4: Generate Attack Traffic and Observe Blocking
-----------------------------------------------------

#. From the attack client, run a sustained high-rate flood::

      wrk -t4 -c100 -d60s http://10.1.10.63/

   If ``wrk`` is not available::

      ab -n 10000 -c 100 -t 60 http://10.1.10.63/

#. While the flood runs, open the BIG-IP TMUI and navigate to
   **Security > Event Logs > DoS > Application Events**.

   You should see entries like:

   .. code-block:: text

      [Blocked] Source IP 10.1.10.100 exceeded TPS threshold (105 TPS, limit 100)
      Duration: 60s | URL: / | Action: Block

#. Navigate to **Security > Reporting > DoS > Dashboard** to see the
   real-time TPS graph and the mitigation timeline.

Task 5: Review Block Page Behavior
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
