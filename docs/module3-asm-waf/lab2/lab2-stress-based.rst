Lab 2: Stress-Based Detection
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
     - Stress-based (Lab 2)
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

Task 1: Switch the Shared Profile to Stress-Based Detection
-----------------------------------------------------------

This lab reuses the **shared ``lab-dos-tps`` profile** from Lab 1 — already
attached to ``vs-lab-dos`` with the ``L7-DOS_BOT_Logger`` log profile. You change
which detection mode is active: quiet Lab 1's per-IP TPS rule, and turn on
stress-based detection.

#. Navigate to **Security > DoS Protection > Protection Profiles**, open
   ``lab-dos-tps``, and select **Application Security**.

#. In **TPS-based Detection**, **disable By Source IP** so Lab 1's per-IP rate
   rule stays quiet during this lab. **(CLI)**::

      tmsh modify security dos profile lab-dos-tps application modify { lab-dos-tps { \
          tps-based { ip-rate-limiting disabled } } }

#. Open **Behavioral & Stress-based (D)DoS Detection** and set **Operation Mode**
   = **Blocking** and **Thresholds Mode** = **Automatic**. Stress-based uses
   *auto-calculated* thresholds — the system learns normal server stress, so there
   is no manual latency %% to enter.

#. Under **Stress-based Detection and Mitigation → By Source IP**, tick a
   mitigation to apply when a source drives server stress — **Request Blocking**
   (optionally **Client Side Integrity Defense** / **CAPTCHA Challenge**).

#. *(Behavioral engine)* Under **Behavioral Detection and Mitigation → By Bad
   Actors Behavior / Signatures**, **Bad actors behavior detection** and **Request
   signatures detection** are the ML layer; the **Mitigation** dropdown
   (Transparent → Conservative → Standard → Aggressive protection) sets how hard it
   acts. Leave the default for this lab.

#. **Prevention Duration** controls ramp-up/down: **Escalation Period** (time at
   each mitigation step) and **De-escalation Period** (how long stress must stay
   normal before relaxing) — defaults here are 120 s / 7200 s.

   .. note::

      Automatic (stress) thresholds need a **learning period** of normal traffic
      before they are effective — run the baseline (Task 2) first. Capture the live
      settings to confirm the exact keywords for your build::

         tmsh list security dos profile lab-dos-tps application | grep -A25 stress-based

#. Click **Update**.

Task 2: Establish a Latency Baseline
--------------------------------------

#. **(kali)** Run the baseline traffic script to allow BIG-IP to learn normal
   server response times::

      bash /home/ec2-user/lab/scripts/setup/baseline-traffic.sh http://10.1.10.63 300

   Allow this to run for at least 5 minutes.

#. In the TMUI, navigate to **Security > Reporting > DoS > Dashboard** (set
   **Real Time: ON**) and confirm server latency is being tracked under **Virtual
   Servers Health** / **System Health**.

Task 3: Simulate a Slow Server Under Attack
--------------------------------------------

#. Open the **Web Shell** for the Hackazon server (UDF UI; mgmt ``10.1.1.5``,
   pool member ``10.1.20.20``) — it drops you in as root. The backend is an
   **Apache container**, so induce latency by starving the container's CPU from
   the host (no in-container tooling required)::

      docker ps                                  # note the Hackazon container name/id
      docker update --cpus=0.1 <hackazon-container>

   With only a fraction of a CPU, the container's response times climb under the
   attack load in Task 2 — that rising server latency is exactly what
   stress-based detection keys on.

   .. note::

      This backend runs **Apache**, not nginx, so the older ``limit_req_zone``
      config edit does not apply. If your Docker build doesn't support live
      ``--cpus`` updates, peg the CPU from inside instead::

         docker exec -d <hackazon-container> sh -c 'while :; do :; done'   # repeat a few times

      Either way the goal is the same: make the backend respond slowly under load.

#. From the attack client, generate a high-concurrency load::

      bash /home/ec2-user/lab/scripts/attack/http-flood.sh http://10.1.10.63 60 80

#. Observe in **Security > Reporting > DoS > Dashboard** (Real Time: ON):

   - **Virtual Servers Health** for ``vs-lab-dos`` degrades as **Server Latency**
     climbs above baseline
   - an attack appears in the **Attacks** table (Vector: Application, a stress
     trigger)
   - the attacking sources show in the right-rail **Transaction Origins** /
     **Client IP Addresses** panels and are being throttled

Task 4: Verify Proportional Throttling (attacker throttled, others served)
--------------------------------------------------------------------------

#. **(superjump — legitimate client)** While the attack is still running, open the
   in-browser **Firefox** on superjump (UDF **ACCESS > FIREFOX**, a different
   source than the attacker) and browse to ``http://10.1.10.63/`` — the full
   **Hackazon** page still loads. Stress-based mitigation throttles the sources
   *causing* the latency, not legitimate clients.

#. **(kali, low-rate)** Optionally quantify it — a low-rate client keeps normal
   latency and **200** responses while the flood is throttled::

      for i in $(seq 1 10); do
          curl -so /dev/null -w "Time: %{time_total}s Code: %{http_code}\n" http://10.1.10.63/
          sleep 0.5
      done

#. **(TMUI)** In **Security > Event Logs > DoS > Application Events**, the episode
   shows **Detection Mode: DOS L7 attack** on a stress trigger; the **Suspicious
   entity** rows name the sources contributing most to latency (the attacker).
   Confirm the Firefox client's source is *not* listed.

#. Compare to Lab 1 (TPS): there, any source over the rate threshold is blocked
   regardless of server impact; stress-based only mitigates when the server is
   actually stressed and targets the heaviest contributors.

Task 5: Clean Up
-----------------

#. In the Hackazon **Web Shell**, remove the artificial stress — restore the
   container's CPU (``0`` = no limit), or restart it if you pegged CPU inside::

      docker update --cpus=0 <hackazon-container>
      # or, if you used the busy-loop fallback:  docker restart <hackazon-container>

#. Verify server response times return to baseline in **Security > Reporting >
   DoS > Dashboard**.

#. Restore the shared profile for later labs — re-enable By Source IP TPS
   detection if you want Lab 1 behaviour back::

      tmsh modify security dos profile lab-dos-tps application modify { lab-dos-tps { \
          tps-based { ip-rate-limiting enabled } } }

Questions
~~~~~~~~~

- A legitimate user running an automated report that makes 200 requests in
  10 seconds may cause server latency to rise. How does stress-based detection
  handle this compared to TPS-based?
- Stress-based detection de-escalates mitigation when latency returns to
  normal. What is the risk if the de-escalation period is set too short?
