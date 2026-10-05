Lab 2: Behavioral DoS (BADoS)
==============================

Behavioral DoS (BADoS) uses machine learning to model **normal** traffic, then
detects and mitigates anomalies automatically — no explicit thresholds. This lab
drives the blueprint's ready-made BaDOS demo from kali and validates it in
the native **Security > Overview > DoS → Behavioral DoS** dashboard, then inspects
the dynamic signatures BADoS generates.

.. list-table:: Lab environment
   :header-rows: 1
   :widths: 26 30 44

   * - Role
     - Access
     - Notes
   * - Traffic (baseline + attack)
     - kali — Web Shell (root)
     - All from kali, split by source IP: baseline binds ``10.1.10.100`` (good),
       the attack binds ``10.1.10.200`` (bad). The demo's ``XFF_mixed_Attacker_Good``
       iRule on ``10.1.10.61`` maps ``.100`` → good and ``.200`` → attacker
   * - Validation dashboard
     - TMUI — **Security > Overview > DoS**
     - Native **BIG-IP Dashboard → Behavioral DoS** (Protected Applications
       status, Server Stress, RPS threshold/baseline, Detected Attacks) — no
       Grafana needed
   * - Protected VS
     - ``vs_Hackazon_I`` — ``10.1.10.61``
     - Blueprint's BaDoS demo VS: ``Hackazon_BaDOS`` profile, ``XFF-http``,
       the ``XFF_mixed_Attacker_Good`` iRule, and ``L7-DOS_BOT_Logger`` — all
       pre-wired

.. note::

   **Run-from key.** **(kali)** = kali attack client via its UDF Web Shell;
   **(TMUI)** = BIG-IP GUI — the **Security > Overview > DoS → Behavioral DoS**
   dashboard.

.. note::

   This lab reuses the environment's ready BaDOS demo, so the good-vs-bad-actor
   split, XFF handling, and logging are already configured on ``vs_Hackazon_I`` —
   there is nothing to build first — it is **entirely kali-driven**: the good
   baseline and the attack both originate from kali, distinguished only by source
   IP (``.100`` good vs ``.200`` attacker). You validate from the BIG-IP GUI. (For a
   build-it-yourself variant on ``vs-lab-dos``, see *Alternative* at the end.)

Task 1: Generate baseline traffic
---------------------------------

BADoS needs a learning period on normal traffic before it can spot anomalies.

#. **(kali)** The Web Shell opens as **root** in root's home, but the prebuilt
   demo scripts live in ``/home/ec2-user/`` (not ``/root``). ``cd`` there before
   running anything — ``baseline_menu.sh`` also reads
   ``./source/useragents_with_bots.txt`` and ``./source/urls.txt`` by relative
   path, so it must be launched from that directory::

      cd /home/ec2-user/     # prompt becomes root@kali:/home/ec2-user#

#. **(kali — Web Shell #1)** Start the **increasing** baseline pattern and leave
   it running in this shell::

      ./baseline_menu.sh
      # choose 1  (increasing)

#. **(kali — Web Shell #2)** Open a **second** kali Web Shell (``cd
   /home/ec2-user/`` again) and start the **alternate** baseline::

      ./baseline_menu.sh
      # choose 2  (alternate)

   .. note::

      The UDF Web Shell doesn't pass ``screen``'s detach keystroke (Ctrl+a d), so
      instead of backgrounding with ``screen``, open a **separate Web Shell per
      long-running stream** — UDF allows several shells to the same host — and leave
      each running. Stop one with **Ctrl+c** in its own shell.

   Both patterns source from ``10.1.10.100`` with randomised user-agents and URLs,
   so BADoS learns a model built from many apparent legitimate clients.

Task 2: Confirm learning
------------------------

#. **(TMUI)** Open **Security > Overview > DoS** and set the **Dashboard** selector
   to **Behavioral DoS**. In **Protected Applications**, select
   ``/Common/vs_Hackazon_I`` (profile ``Hackazon_BaDOS``) — its **Status** should
   read **Calm**.

#. Watch **Client HTTP Transactions**: the **Baseline** line settles in and tracks
   **Incoming Requests** as BADoS learns normal traffic. Let the baseline establish
   before attacking — behavioral detection needs a learning period and won't flag
   an anomaly it has no baseline for.

Task 3: Launch the attack
-------------------------

#. **(kali)** With the baseline still running, start the attack from a second
   Web Shell::

      cd /home/ec2-user/
      ./AB_DOS.sh
      # choose 1  (Attack start - similarity)

   ``AB_DOS.sh`` runs looped ``ab`` floods against ``10.1.10.61``, bound to source
   ``10.1.10.200`` so the demo's ``XFF_mixed_Attacker_Good`` iRule stamps them as
   the attacker cluster. Option **2** (*score*) is a heavier variant you can try
   instead. The addresses are set at the top of the script (``VS_ADDR`` /
   ``SRC_ADDR*``) — edit them there if your deployment differs.

.. note::

   The attack binds to ``10.1.10.200``, so kali must have that secondary address
   configured (it does in the blueprint). Confirm with ``ip addr | grep 10.1.10``.

Task 4: Validate mitigation
---------------------------

On the **Security > Overview > DoS → Behavioral DoS** dashboard
(``/Common/vs_Hackazon_I``):

#. **Protected Applications → Status** flips from **Calm** to **Under Attack**, and
   the **Detected Attacks** table gets a row (Attack Id / Start Time / Duration).

#. **Client HTTP Requests & Transactions** shows **Incoming Requests** spike above
   the **RPS Threshold** while **Server Stress** rises — BADoS has detected the
   anomaly.

#. Within a minute or two, **Server Stress** falls back and **Successful
   Transactions** stay healthy **even though the attack is still running** — BADoS
   generated dynamic signatures and is mitigating the bad traffic while legitimate
   baseline requests keep flowing. The gap between **Incoming Requests** and
   **Successful / Passthrough** is the dropped attack traffic.

#. **(TMUI)** **Security > Event Logs > DoS > Application Events** — per-attack
   detail (anomaly %, mitigated actors, action), populated because
   ``vs_Hackazon_I`` carries the ``L7-DOS_BOT_Logger`` log profile.

Task 5: Examine the signature BADoS generated
---------------------------------------------

When behavioral detection mitigates an attack it **auto-generates a dynamic
signature** describing the attack traffic. Reading it shows *how* BADoS tells the
attack apart from normal traffic.

#. **(TMUI)** Go to **Security > DoS Protection > Signatures** (the tab next to
   **Protection Profiles**). Under the **Dynamic** section is an auto-generated
   signature named ``HTTPSig…`` tied to your attack — Family **HTTP**, **Context**
   ``vs_Hackazon_I``, **Profile** ``Hackazon_BaDOS``, and the same **Attack ID**
   you saw on the dashboard.

#. Read the state columns:

   - **Deployment State: Mitigate** — the signature is actively blocking matching
     traffic (vs *Detect* / *Learn*).
   - **Approval State** — dynamic signatures start unapproved; *Manually-approved*
     means a human vetted it (see Lab 5).
   - **Threshold EPS** (Detection / Mitigation / Dropped / Current) — the
     events-per-second counters driving it.

#. Expand the row and read the **Predicates String** — the attack's fingerprint,
   learned automatically. For the ``AB_DOS.sh`` flood it looks like::

      ( http.x_forwarded_for_header_exists eq true ) and
      ( http.referer_header_exists eq true ) and
      ( http.pragma_header_exists eq true ) and
      ( http.accept_encoding_header_exists eq true ) and
      ( http.accept contains application ) and
      ( http.cache_control_header_exists eq true ) and
      ( http.headers_count eq 11 ) and
      ( http.unknown_header_exists eq true ) and
      ( http.hdrorder hashes-to 11 ) and
      ( http.cache_control hashes-to 14 ) and
      ( http.referer hashes-like http://10.0.2.1/none.html )

   Each predicate is a trait BADoS found common to the attack but **not** to the
   learned baseline — the specific header set, the header *count* (11) and *order*
   hash, and the tell-tale ``Referer: http://10.0.2.1/none.html`` the attack script
   sends. Together they match the attack precisely while leaving normal traffic
   alone — which is why legitimate clients kept being served during the attack.

   .. note::

      **Why predicate mitigation beats a rate limit here.** The signature filters
      on the *request's shape*, not its source — so it mitigates the attack on
      different terms than the per-IP and TPS limits in Labs 1 and 3:

      - **Source-independent.** It drops anything matching the attack fingerprint
        regardless of IP, so an attacker rotating thousands of IPs — or hiding
        behind the same NAT/CDN as real users — is still caught. A per-IP limit
        only sees source IP, so it misses a distributed/low-and-slow attacker that
        stays under the threshold.
      - **No collateral damage.** Because the predicates match traits common to the
        attack and *absent* from the learned baseline, legitimate users keep being
        served even from the same IPs — the opposite of per-IP Block All, which
        also blocks innocent users sharing a NATed address (the shared-NAT problem
        from Module 1 Lab 1). That's the ``47.8k`` blocked transactions with the
        server-side graph staying flat.
      - **Automatic and adaptive.** BADoS derives the predicate set from live
        traffic in seconds — you don't have to know or hand-tune the right
        threshold in advance (contrast Lab 1, where you had to find a TPS number
        that fit the backend).

      The trade-off: predicate mitigation is sharper but needs the attack to have a
      learnable, distinct shape and a good baseline; a rate limit is blunt but
      simple, deterministic, and needs no learning. In production you layer them —
      behavioral/predicate for precision, rate limits as a coarse backstop.

#. Expand **Most Recent Attacks**: **Accuracy 100%** and a non-zero **Current EPS**
   mean the signature is matching live attack traffic; **Detection / Mitigation
   Threshold EPS** show the rates at which it acts.

#. *(optional)* With the signature selected, use **Make Persistent** to keep it
   beyond this attack (hand-off to :doc:`../lab5/lab5-persistent-signatures`),
   **Set Deployment State**, or **Set Threshold Mode**.

Teardown
--------

#. **(kali)** Stop the attack: press **Ctrl+c** to break the flood loop, then in
   the ``AB_DOS.sh`` menu choose **3** (*Attack end*) to ``killall ab``, then
   **4** (*Quit*).

#. **(kali)** Stop the baseline streams — press **Ctrl+c** in each of the Web
   Shells running ``baseline_menu.sh`` (or, from any shell)::

      pkill -f baseline_menu.sh

Alternative: build-it-yourself on ``vs-lab-dos``
------------------------------------------------

To construct an equivalent demo from scratch on the lab VIP instead of the
prebuilt one, use ``vs-lab-dos`` with the shared ``lab-dos-tps`` profile (enable
**Behavioral & Stress-based Detection** on it), swap it to the
``XFF-http`` profile, and attach ``configs/irules/xff-traffic-shaping.tcl`` — then
generate a good baseline and an attack from sources the iRule classifies
differently, and validate in the TMUI (**Security > DoS Protection > DoS
Overview** → Bad Actors). Set the iRule's ``good``/``attack`` source lists to
match whatever hosts you drive traffic from (e.g. win-client + the
``C:\lab\baseline-traffic.ps1`` baseline, or kali's two addresses as the
prebuilt demo does).

Questions
~~~~~~~~~

- The dashboard shows **Server Stress** recover *while the attack is still
  running*. What did BADoS do between "under attack" and "healthy again", and why
  is that different from a static rate limit?
- The attacker is blacklisted via **dynamic signatures**. How is that different
  from the **bad-actor greylist**, and when would each be the mitigation you see?
- A promoted dynamic signature (Task 5) becomes persistent. What do you gain by
  persisting it, and what's the risk of persisting one generated during a noisy,
  mixed attack?
