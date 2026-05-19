Lab 4: Stress-Based Detection
==============================

Stress-based detection uses **server-side health signals** — response latency
and error rates — to identify which clients are contributing to server stress,
and throttles those sources proportionally. Unlike TPS-based mode (which blocks
sources at a raw request rate), stress-based detection throttles sources
*relative to the stress they cause*, making it less likely to penalize
legitimate heavy users.

.. list-table:: Stress-Based vs. TPS-Based Comparison
   :header-rows: 1
   :widths: 35 32 33

   * - Property
     - TPS-based (Lab 1)
     - Stress-based (Lab 4)
   * - Trigger
     - Request rate
     - Server latency / error rate
   * - Granularity
     - Per source IP or URL
     - Per source contributing to stress
   * - Penalizes heavy-but-legitimate users
     - Possible
     - Less likely
   * - Requires baseline learning
     - No
     - Yes
   * - Effective against slow attacks
     - Limited
     - Yes

Task 1: Configure Stress-Based Detection
-----------------------------------------

#. Navigate to **Security > DoS Protection > DoS Profiles**, open
   ``lab-dos-bados``, and expand **Behavioral & Stress-based Detection**.

#. Enable **Stress-based Detection** and configure:

   .. list-table::
      :header-rows: 1
      :widths: 50 50

      * - Setting
        - Value
      * - Latency Increase Threshold
        - 200%
      * - TPS Increase Threshold
        - 500%
      * - Minimum TPS for Detection
        - 10

   .. note::

      **Latency Increase Threshold: 200%** means stress-based detection
      triggers when server response time rises to 3× the learned baseline
      (baseline + 200% of baseline).

#. Click **Finished** and apply the policy.

Task 2: Establish a Latency Baseline
--------------------------------------

#. Run the baseline traffic script to allow BIG-IP to learn normal server
   response times::

      bash ~/lab/scripts/setup/baseline-traffic.sh http://10.1.10.100 300

   Allow this to run for at least 5 minutes.

#. In the TMUI, navigate to **Security > DoS Protection > DoS Overview** and
   confirm the baseline latency is being tracked.

Task 3: Simulate a Slow Server Under Attack
--------------------------------------------

#. On the web server (``10.1.20.10``), start a script that introduces
   artificial latency for high-concurrency requests (simulating a server
   under load)::

      ssh root@10.1.20.10 \
        "echo 'limit_req_zone \$binary_remote_addr zone=slow:10m rate=5r/s;' \
         >> /etc/nginx/nginx.conf && nginx -s reload"

#. From the attack client, generate a high-concurrency load::

      bash ~/lab/scripts/attack/http-flood.sh http://10.1.10.100 60 80

#. Observe in **Security > DoS Protection > DoS Overview**:

   - **Server Latency** graph rises above the baseline
   - **Stress-based Detection: Active** appears
   - The **Bad Actors** table shows which source IPs are contributing the
     most to latency and are being throttled

Task 4: Verify Proportional Throttling
----------------------------------------

#. From a second terminal (using a different source IP or a low-rate
   client), send requests during the attack::

      for i in $(seq 1 10); do
          curl -so /dev/null -w "Time: %{time_total}s Code: %{http_code}\n" \
               http://10.1.10.100/
          sleep 0.5
      done

   Expected result: the low-rate client continues to receive **200** responses
   with normal latency. BIG-IP has throttled the high-rate attacker but left
   the low-rate client unaffected.

#. Compare this to TPS-based behavior from Lab 1 — in TPS mode, any source
   exceeding the threshold is blocked regardless of server impact.

Task 5: Clean Up
-----------------

#. Remove the artificial latency from the web server::

      ssh root@10.1.20.10 \
        "sed -i '/limit_req_zone/d' /etc/nginx/nginx.conf && nginx -s reload"

#. Verify server response times return to baseline in the DoS Overview
   dashboard.

Questions
~~~~~~~~~

- A legitimate user running an automated report that makes 200 requests in
  10 seconds may cause server latency to rise. How does stress-based detection
  handle this compared to TPS-based?
- Stress-based detection de-escalates mitigation when latency returns to
  normal. What is the risk if the de-escalation period is set too short?
