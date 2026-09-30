Lab 2: Behavioral DoS (BADoS)
==============================

Behavioral DoS (BADoS) uses machine learning to model **normal** traffic, then
detects and mitigates anomalies automatically — no explicit thresholds. This lab
drives the blueprint's ready-made BaDOS demo from kali and validates it in
**Grafana**, then inspects the dynamic signatures BADoS generates.

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
     - win-client — Guacamole RDP → Chrome
     - **Grafana** (``admin``/``admin``) → *Health and Mitigations*
   * - Protected VS
     - ``vs_Hackazon_I`` — ``10.1.10.61``
     - Blueprint's BaDoS demo VS: ``Hackazon_BaDOS`` profile, ``XFF-http``,
       the ``XFF_mixed_Attacker_Good`` iRule, and ``L7-DOS_BOT_Logger`` — all
       pre-wired

.. note::

   **Run-from key.** **(kali)** = kali attack client via its UDF Web Shell;
   **(win-client)** = Windows client via superjump Guacamole RDP (Chrome →
   Grafana); **(TMUI)** = BIG-IP GUI.

.. note::

   This lab reuses the environment's ready BaDOS demo, so the good-vs-bad-actor
   split, XFF handling, and logging are already configured on ``vs_Hackazon_I`` —
   there is nothing to build first — it is **entirely kali-driven**: the good
   baseline and the attack both originate from kali, distinguished only by source
   IP (``.100`` good vs ``.200`` attacker). Win-client is used only to view
   Grafana. (For a build-it-yourself variant on ``vs-lab-dos``, see *Alternative*
   at the end.)

Task 1: Generate baseline traffic
---------------------------------

BADoS needs a learning period on normal traffic before it can spot anomalies.

#. **(kali)** The Web Shell opens as **root** in root's home, but the prebuilt
   demo scripts live in ``/home/ec2-user/`` (not ``/root``). ``cd`` there before
   running anything — ``baseline_menu.sh`` also reads
   ``./source/useragents_with_bots.txt`` and ``./source/urls.txt`` by relative
   path, so it must be launched from that directory::

      cd /home/ec2-user/     # prompt becomes root@kali:/home/ec2-user#

#. **(kali)** Start the **increasing** baseline pattern inside a detachable
   ``screen`` so it keeps running::

      screen        # press ENTER at the banner
      ./baseline_menu.sh
      # choose 1  (increasing)

   Detach with **Ctrl+a** then **d** (the stream keeps running in the background).

#. **(kali)** Start the **alternate** baseline pattern the same way::

      screen
      ./baseline_menu.sh
      # choose 2  (alternate)

   Detach again with **Ctrl+a** then **d**. (``screen -ls`` lists both sessions.)
   Both patterns source from ``10.1.10.100`` with randomised user-agents and
   URLs, so BADoS learns a model built from many apparent legitimate clients.

Task 2: Confirm learning in Grafana
-----------------------------------

#. **(win-client)** RDP to the Windows client (superjump Guacamole), launch
   **Chrome**, and open the **Grafana** bookmark. Log in ``admin`` / ``admin``.

#. **(win-client)** Go to **Home > Health and Mitigations**. Wait for
   **HTTP Threshold Learning** to turn **GREEN** before attacking — that is
   BADoS signalling it has a usable baseline (equivalent to *Behavioral Analysis
   Status: Ready* in the TMUI).

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

Task 4: Validate mitigation in Grafana
--------------------------------------

#. **(win-client)** In **Home > Health and Mitigations** you should see
   **UNDER ATTACK** and the **Health** score degrade (**> 0.45**).

#. **(win-client)** After a few minutes, **Health returns to good (< 0.45)** —
   BADoS has generated dynamic signatures and is mitigating the attack while it
   is still in progress.

#. **(win-client)** On the **Home** dashboard, open the **Bad Actors** graph —
   the offending sources are now blacklisted because they match the dynamic
   signatures, while legitimate baseline traffic keeps flowing.

Task 5: Inspect the dynamic signatures
--------------------------------------

#. **(TMUI)** Go to **Security > DoS Protection > Signatures** and select the
   **Dynamic** tab. BADoS auto-generated these from the attack traffic; each
   expands to show its predicates and recent attacks.

#. **(TMUI)** *(optional)* Select an effective signature and **Make Persistent**
   to keep it beyond this attack — this is the hand-off into
   :doc:`../lab5/lab5-persistent-signatures` (Custom Persistent DoS Signatures).

Teardown
--------

#. **(kali)** Stop the attack: press **Ctrl+c** to break the flood loop, then in
   the ``AB_DOS.sh`` menu choose **3** (*Attack end*) to ``killall ab``, then
   **4** (*Quit*).

#. **(kali)** Stop the baseline ``screen`` sessions::

      screen -ls                    # list the detached baseline sessions
      # reattach each (screen -r <id>), Ctrl+c to stop, then exit — or:
      pkill -f baseline_menu.sh

Alternative: build-it-yourself on ``vs-lab-dos``
------------------------------------------------

To construct an equivalent demo from scratch on the lab VIP instead of the
prebuilt one, use ``vs-lab-dos`` with ``lab_dos_bados_profile``, swap it to the
``XFF-http`` profile, and attach ``configs/irules/xff-traffic-shaping.tcl`` — then
generate a good baseline and an attack from sources the iRule classifies
differently, and validate in the TMUI (**Security > DoS Protection > DoS
Overview** → Bad Actors). Set the iRule's ``good``/``attack`` source lists to
match whatever hosts you drive traffic from (e.g. win-client + the
``C:\lab\baseline-traffic.ps1`` baseline, or kali's two addresses as the
prebuilt demo does).

Questions
~~~~~~~~~

- Grafana shows Health recover to **< 0.45** *while the attack is still running*.
  What did BADoS do between "under attack" and "healthy again", and why is that
  different from a static rate limit?
- The attacker is blacklisted via **dynamic signatures**. How is that different
  from the **bad-actor greylist**, and when would each be the mitigation you see?
- A promoted dynamic signature (Task 5) becomes persistent. What do you gain by
  persisting it, and what's the risk of persisting one generated during a noisy,
  mixed attack?
