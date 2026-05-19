Lab 2: Behavioral DoS (BADoS)
==============================

Behavioral DoS uses machine learning to build a model of **normal** traffic
patterns, then detects and mitigates anomalies automatically — without
requiring explicit thresholds. This lab walks through the full BADoS lifecycle:
baseline learning, attack detection, and automatic mitigation.

.. important::

   BADoS requires a **learning period** before it can detect anomalies. Allow
   at least 10 minutes of normal baseline traffic (Task 1) before launching
   the simulated attack (Task 3). Skipping this step will result in the system
   either failing to detect or over-detecting the attack.

Task 1: Generate Baseline Traffic
----------------------------------

#. SSH to the attack client (``10.1.10.50``).

#. Run the baseline traffic script for at least 10 minutes::

      bash ~/lab/scripts/setup/baseline-traffic.sh http://10.1.10.100 600

   This sends realistic mixed traffic (~20 req/s across several URIs)
   to allow BADoS to build a traffic model.

#. Monitor learning progress in the TMUI:

   - Navigate to **Security > DoS Protection > DoS Overview**
   - Look for **Behavioral Analysis Status: Learning** transitioning to
     **Behavioral Analysis Status: Ready**

Task 2: Create the BADoS Profile
----------------------------------

#. Navigate to **Security > DoS Protection > DoS Profiles** and click
   **Create**.

#. Set the **Name** to ``lab-dos-bados``.

#. Under **Application**, expand **Behavioral & Stress-based Detection**.

#. Configure:

   .. list-table::
      :header-rows: 1
      :widths: 50 50

      * - Setting
        - Value
      * - Operation Mode
        - Blocking
      * - Bad Actor Detection
        - Enabled
      * - Request Blocking Mode
        - Block always
      * - Escalation Period
        - 90 seconds
      * - De-escalation Period
        - 360 seconds

#. Under **Heavy URL Protection**, enable **Automatic Detection**.

#. Leave TPS-based Detection disabled to isolate BADoS behavior.

#. Click **Finished** and attach ``lab-dos-bados`` to **lab-policy**.

Task 3: Launch the Simulated Attack
------------------------------------

#. From the attack client, run the HTTP flood script::

      bash ~/lab/scripts/attack/http-flood.sh http://10.1.10.100 60 100

   This sends 100 concurrent connections for 60 seconds — a 5× spike over
   the 20 req/s baseline.

#. Observe BADoS detection in the TMUI:

   Navigate to **Security > DoS Protection > DoS Overview**.

   You should see:

   - **Attack Status: Detected** within 20–30 seconds of the flood starting
   - **Mitigation: Active** as BADoS begins throttling bad actors
   - The ``Bad Actors`` table populating with the attacker IP and its
     anomaly score

Task 4: Inspect the Mitigation Detail
----------------------------------------

#. Navigate to **Security > Event Logs > DoS > Application Events**.

   Observe entries showing:

   .. code-block:: text

      [Attack Detected] Behavioral anomaly — request rate deviation 420%
      Mitigated actors: 1 | Protected URL: /
      Mitigation: Rate shaping applied to 10.1.10.50

#. Navigate to **Security > Reporting > DoS > Dashboard**.

   The dashboard shows:

   - **TPS** graph with the attack spike highlighted
   - **Mitigated TPS** showing traffic absorbed by BIG-IP
   - **Server TPS** showing the rate actually reaching the pool member

Task 5: Verify Legitimate Traffic is Preserved
------------------------------------------------

#. From a **different** client IP (or using a second terminal with a
   different source IP), send requests during the attack::

      curl -so /dev/null -w "%{http_code}\n" http://10.1.10.100/

   Expected result: **200** — BADoS targets individual bad actors, not
   all traffic to the virtual server.

.. note::

   This is the key differentiator between BADoS and TPS-based blocking:
   BADoS identifies and suppresses the specific sources driving the anomaly
   while allowing other traffic to pass. TPS-based mode blocks all sources
   exceeding the threshold, including innocent shared-NAT users.

Questions
~~~~~~~~~

- BADoS uses a ``De-escalation Period`` of 360 seconds. What does this mean,
  and why is it set longer than the ``Escalation Period``?
- If the baseline traffic rate doubles permanently (e.g., a successful product
  launch), will BADoS continue to work correctly? Why or why not?
