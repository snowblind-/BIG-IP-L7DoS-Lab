Lab 1: TPS-Based DoS Protection
================================

This lab configures explicit **transactions-per-second (TPS)** thresholds in
an ASM DoS profile. When a source IP or URL exceeds the threshold, BIG-IP
blocks, challenges, or rate-limits that source until traffic normalizes.
TPS-based protection is the simplest WAF DoS mode — it requires no learning
period and triggers on known numeric thresholds.

Task 1: Verify ASM is Provisioned
-----------------------------------

#. SSH to the BIG-IP::

      ssh admin@10.1.1.245

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

#. In the TMUI, navigate to **Security > DoS Protection > DoS Profiles**.

#. Click **Create**.

#. Set the **Name** to ``lab-dos-tps``.

#. Under the **Application** section, expand **TPS-based Detection**.

#. Enable **By Source IP** and configure:

   .. list-table::
      :header-rows: 1
      :widths: 50 50

      * - Setting
        - Value
      * - Detection Mode
        - Blocking
      * - TPS Increased By
        - 500%
      * - TPS Reached
        - 100
      * - Blocking Duration
        - 60 seconds

#. Enable **By URL** and configure:

   .. list-table::
      :header-rows: 1
      :widths: 50 50

      * - Setting
        - Value
      * - TPS Increased By
        - 200%
      * - TPS Reached
        - 1000
      * - Blocking Duration
        - 60 seconds

#. Leave **Behavioral Detection** disabled for this lab.

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

      wrk -t4 -c100 -d60s http://10.1.10.100/

   If ``wrk`` is not available::

      ab -n 10000 -c 100 -t 60 http://10.1.10.100/

#. While the flood runs, open the BIG-IP TMUI and navigate to
   **Security > Event Logs > DoS > Application Events**.

   You should see entries like:

   .. code-block:: text

      [Blocked] Source IP 10.1.10.50 exceeded TPS threshold (105 TPS, limit 100)
      Duration: 60s | URL: / | Action: Block

#. Navigate to **Security > Reporting > DoS > Dashboard** to see the
   real-time TPS graph and the mitigation timeline.

Task 5: Review Block Page Behavior
------------------------------------

#. While the flood is running (or immediately after), send a manual request
   from the attack client::

      curl -v http://10.1.10.100/

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
  (e.g., stricter for ``/api/login`` than for ``/``)?
