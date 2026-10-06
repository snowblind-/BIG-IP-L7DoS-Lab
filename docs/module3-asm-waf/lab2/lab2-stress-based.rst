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

Task 1: Create a Stress-Based DoS Profile and Switch the Virtual Server to It
-----------------------------------------------------------------------------

Rather than reuse Lab 1's profile, build a **dedicated** stress-based profile from
scratch and switch ``vs-lab-dos`` to it. A virtual server carries **one** DoS
profile at a time, so attaching ``lab-dos-stress`` replaces ``lab-dos-tps``; Task 5
puts the shared profile back.

#. **(TMUI)** Navigate to **Security > DoS Protection > Protection Profiles** and
   click **Create**. Set **Name** = ``lab-dos-stress``.

#. Under **Application Security**, open **Behavioral & Stress-based (D)DoS
   Detection** and set **Operation Mode** = **Blocking** and **Thresholds Mode** =
   **Automatic**. Stress-based uses *auto-calculated* thresholds — the system learns
   normal server stress, so there is no manual latency %% to enter. Leave
   **TPS-based Detection** disabled: this profile detects by **server stress**, not
   raw request rate.

#. Under **Stress-based Detection and Mitigation → By Source IP**, enable a
   **two-step mitigation ladder** so you can watch mitigation *escalate* as the
   attack persists: tick **Client Side Integrity Defense** (the gentler first step)
   **and** **Request Blocking → Block All** (the harder second step). BIG-IP applies
   the mildest enabled method first and escalates to the next after the Escalation
   Period if the source keeps driving stress.

   .. note::

      Client Side Integrity Defense is a JavaScript challenge, so a non-JS client
      (the curl/ab flood) cannot satisfy it and is dropped at that step; as the
      flood keeps server stress high, mitigation then escalates to **Block All** —
      the step-up you observe in Task 3.

#. *(Behavioral engine)* Under **Behavioral Detection and Mitigation**, **Bad
   actors behavior detection** and **Request signatures detection** are the ML
   layer; the **Mitigation** dropdown (Transparent → Conservative → Standard →
   Aggressive protection) sets how hard it acts. Leave the default for this lab.

#. **Prevention Duration** drives the escalation timing. The stress defaults are
   long — Escalation 120 s / **De-escalation 7200 s (two hours)** — so mitigation
   would never relax in lab time. Shorten **both** so the full cycle is visible:
   **Escalation Period = 15 s** (how long mitigation stays at each step before
   escalating) and **De-escalation Period = 30 s** (how long stress must stay normal
   before mitigation relaxes). With these, mitigation steps from Client Side
   Integrity Defense to Block All about 15 s into a sustained attack, and relaxes
   ~30 s after it stops.

   .. note::

      Short periods make the demo snappy but can cause **flapping** (mitigation
      toggling on/off) when real traffic hovers near the threshold — use longer
      values in production.

#. Click **Finished**.

   **(CLI equivalent)** — create the profile and its Application Security container;
   configure the stress/behavioral specifics in the UI above, then capture the exact
   17.5 keywords for your build before scripting them::

      tmsh create security dos profile lab-dos-stress
      tmsh modify security dos profile lab-dos-stress application add { lab-dos-stress { } }
      tmsh list security dos profile lab-dos-stress application | grep -A25 -E "behavioral|stress-based"
      tmsh save sys config

#. **Switch the virtual server to the new profile.** Navigate to **Local Traffic >
   Virtual Servers > vs-lab-dos > Security > Policies**. Set **DoS Protection
   Profile** = **Enabled** and select ``lab-dos-stress`` (this replaces
   ``lab-dos-tps``). Ensure **Log Profile** = **Enabled** with ``L7-DOS_BOT_Logger``
   in **Selected**, then **Update**.

   **(CLI)** — a VS holds one DoS profile, so remove the TPS profile before adding
   the stress profile; run the adds on separate lines::

      tmsh modify ltm virtual vs-lab-dos profiles delete { lab-dos-tps }
      tmsh modify ltm virtual vs-lab-dos profiles add { lab-dos-stress }
      tmsh modify ltm virtual vs-lab-dos security-log-profiles add { L7-DOS_BOT_Logger }
      tmsh list ltm virtual vs-lab-dos profiles security-log-profiles

   .. note::

      Automatic (stress) thresholds need a **learning period** of normal traffic
      before they are effective — run the baseline (Task 2) first.

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

      bash /home/ec2-user/lab/scripts/attack/http-flood.sh http://10.1.10.63 90 80

   Run it long enough (here 90 s) to outlast the 15 s Escalation Period so the
   mitigation steps up — then let it stop so you can watch the ~30 s de-escalation.

#. Observe in **Security > Reporting > DoS > Dashboard** (Real Time: ON):

   - **Virtual Servers Health** for ``vs-lab-dos`` degrades as **Server Latency**
     climbs above baseline
   - an attack appears in the **Attacks** table (Vector: Application, a stress
     trigger)
   - the attacking sources show in the right-rail **Transaction Origins** /
     **Client IP Addresses** panels and are being throttled

#. **Watch the mitigation escalate.** In **Security > Event Logs > DoS >
   Application Events**, follow the episode for the attacking source: the first
   events show **Client Side Integrity Defense** applied, and after ~15 s of
   continued stress (the Escalation Period) the mitigation **escalates to Block
   All**. About 30 s after the flood stops and latency returns to normal, the
   De-escalation Period relaxes mitigation — the step down is logged too.

   .. note::

      Stress thresholds are automatic and need the Task 2 baseline first; exact
      escalation timing varies with how fast the backend stress is sampled. If you
      don't see the step-up, extend the flood and confirm the Escalation Period is
      15 s. (This lab is not yet live-validated — confirm the escalation sequence on
      your build and adjust the periods to taste.)

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

#. **Switch the virtual server back to the shared profile** for later labs —
   detach ``lab-dos-stress`` and reattach ``lab-dos-tps`` (TMUI: *vs-lab-dos >
   Security > Policies*, set **DoS Protection Profile** back to ``lab-dos-tps``)::

      tmsh modify ltm virtual vs-lab-dos profiles delete { lab-dos-stress }
      tmsh modify ltm virtual vs-lab-dos profiles add { lab-dos-tps }
      tmsh save sys config

   *(Optional)* delete the stress profile if you won't reuse it::

      tmsh delete security dos profile lab-dos-stress

Questions
~~~~~~~~~

- A legitimate user running an automated report that makes 200 requests in
  10 seconds may cause server latency to rise. How does stress-based detection
  handle this compared to TPS-based?
- Stress-based detection de-escalates mitigation when latency returns to
  normal. What is the risk if the de-escalation period is set too short?
