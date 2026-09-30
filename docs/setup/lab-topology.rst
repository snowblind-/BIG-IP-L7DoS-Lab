Lab Setup: Topology and Virtual Servers
========================================

Each protection method in this guide is demonstrated on its **own virtual
server**, all fronting the same Hackazon backend. Using separate VIPs keeps the
methods from interfering with one another and lets you run them side by side
against the same attack. (There's an extra reason to separate the two Bot Defense
VIPs if you deploy DoS profiles via AS3 — see the note under the VS map.)

Topology
--------

.. code-block:: text

   [Attack Client]                     [BIG-IP VE 17.1.0.1]                [Backend]
    kali 10.1.10.100 ───HTTP──▶  vs-lab-irules  10.1.10.55:80 ─┐
                                 vs-lab-ltm     10.1.10.56:80 ─┤
                                 vs-lab-dos     10.1.10.63:80 ─┼─▶ Hackazon_pool ──▶ Hackazon
                                 vs-lab-bot     10.1.10.74:80 ─┘   (existing UDF pool,
                                 mgmt 10.1.1.11                     live member)

Virtual server map
------------------

.. list-table::
   :header-rows: 1
   :widths: 22 18 30 30

   * - Virtual server
     - Address
     - Module / scenarios
     - What to attach
   * - ``vs-lab-irules``
     - ``10.1.10.55:80``
     - Module 1 — iRule rate limiting (1.1–1.5)
     - The iRule under test (``rate-limit-per-ip``, ``rate-limit-per-uri``,
       ``concurrent-conn-limit``, ``sliding-window-429``,
       ``custom-l7dos-signature``)
   * - ``vs-lab-ltm``
     - ``10.1.10.56:80``
     - Module 2 — LTM policies (2.1–2.4)
     - The LTM policy under test, plus ``policy-triggered-rate-limit`` where the
       scenario uses it
   * - ``vs-lab-dos``
     - ``10.1.10.63:80``
     - Module 3 — DoS profile: TPS (3.1), BADoS (3.2), stress (3.4), and the
       DoS-profile Proactive Bot Defense (3.3, Task 1)
     - ``lab_dos_*`` DoS profile (``tps-dos-profile.json`` /
       ``bados-profile.json`` / ``bot-defense-profile.json``). Lab 2 temporarily
       swaps this VS to the ``XFF-http`` profile and attaches the
       ``xff-traffic-shaping`` iRule for bad-actor detection (student steps).
   * - ``vs-lab-bot``
     - ``10.1.10.74:80``
     - Module 3 — standalone Bot Defense profile (3.3, Task 2+): verify
       before/after, per-bot rate limits
     - ``security bot-defense profile lab-bot-defense``
       (``bot-defense-standalone.conf``)
   * - ``vs_Hackazon_I``
     - ``10.1.10.61:80``
     - Pre-built by the UDF blueprint — leave as-is
     - Nothing (unprotected baseline for A/B comparison)

All four lab VIPs point at the blueprint's existing ``Hackazon_pool``, so the
application under test is identical across methods.

.. note::

   **Pool.** The lab uses the UDF blueprint's existing ``Hackazon_pool``, which
   already has a live, monitored Hackazon member — it does **not** create its own
   pool. (An earlier draft created a pool with member ``10.1.20.5:80``, but
   nothing was listening on that address in this blueprint version.) Confirm the
   pool and its member are up before building::

      tmsh list ltm pool Hackazon_pool

.. note::

   **Addresses already in use.** The UDF blueprint pre-builds several demo
   virtual servers on the client subnet — ``.52``, ``.54``, ``.57``, ``.58``,
   ``.59``, ``.61`` (``vs_Hackazon_I``), ``.62``, ``.65``, and ``.66`` — so those
   are taken. The lab uses the free addresses ``.55``, ``.56``, ``.63``, and
   ``.74`` (``.78`` is spare). ``.9`` is the BIG-IP self IP, not a VIP. Check
   before building::

      tmsh list ltm virtual destination
      tmsh list ltm virtual-address

   Leaving ``vs_Hackazon_I`` (``.61``) untouched is handy: it's an unmitigated
   path to the same Hackazon backend, so you can hit it alongside a lab VIP to
   compare "no protection" against each mitigation.

Create the virtual servers
--------------------------

Run once on the BIG-IP (``mgmt 10.1.1.11``). The lab reuses the UDF blueprint's
existing ``Hackazon_pool`` (which already has a live Hackazon member), so no pool
is created here. Adjust the VIP addresses if your deployment differs.

.. code-block:: bash

   # Four virtual servers, all fronting the blueprint's existing Hackazon_pool.
   # SNAT automap so the backend returns via the BIG-IP server-side self IP.
   tmsh create ltm virtual vs-lab-irules destination 10.1.10.55:80 \
       ip-protocol tcp pool Hackazon_pool \
       profiles add { tcp http } source-address-translation { type automap }

   tmsh create ltm virtual vs-lab-ltm destination 10.1.10.56:80 \
       ip-protocol tcp pool Hackazon_pool \
       profiles add { tcp http } source-address-translation { type automap }

   tmsh create ltm virtual vs-lab-dos destination 10.1.10.63:80 \
       ip-protocol tcp pool Hackazon_pool \
       profiles add { tcp http } source-address-translation { type automap }

   tmsh create ltm virtual vs-lab-bot destination 10.1.10.74:80 \
       ip-protocol tcp pool Hackazon_pool \
       profiles add { tcp http } source-address-translation { type automap }

   tmsh save sys config

Atomic build + SCF export
~~~~~~~~~~~~~~~~~~~~~~~~~~~

To create all four VIPs in a single all-or-nothing **transaction** (nothing is
created if any object fails) and export the result as a Single Configuration
File, run ``scripts/setup/create-lab-vips.sh`` on the BIG-IP. It checks that
``Hackazon_pool`` exists and that each address is free (clean early abort — no
dangling transaction prompt), wraps VIP creation in ``create cli transaction`` /
``submit cli transaction``, verifies all four VIPs exist, and only then writes
``/var/local/scf/l7dos-lab.scf``.

.. note::

   An SCF is a **whole-device** configuration snapshot, not just these objects —
   ``tmsh load sys config file l7dos-lab.scf`` *replaces* the entire running
   config (it first backs the old one up to ``/var/local/scf/backup.scf``). To
   pull only the VIPs into an existing box, keep those stanzas in their own file
   and load with ``tmsh load sys config merge file <file>`` instead.

Verify::

   tmsh list ltm virtual one-line | grep vs-lab-
   for ip in 55 56 63 74; do
       curl -s -o /dev/null -w "vs .$ip -> %{http_code}\n" http://10.1.10.$ip/
   done

Each VIP should return the Hackazon application (``200``) before any mitigation
is attached.

.. note::

   Attach only the method being demonstrated to its VIP, and leave the others
   clean. That way a single ``curl`` from kali (``10.1.10.100``) shows exactly
   one mitigation at a time, and you can A/B two methods by changing only the
   destination port-less address (``.55`` vs ``.63``, etc.).

.. important::

   Keep ``vs-lab-dos`` and ``vs-lab-bot`` separate for a clean, isolated demo.
   There is also a hard conflict **if you deploy DoS profiles via AS3**: AS3
   auto-generates a shadow ``f5_appsvcs_<dos-profile>_botDefense`` profile, which
   collides with a standalone Bot Defense profile on the same VS
   (duplicate-profile error). Building profiles via UI/CLI doesn't create the
   shadow, but the split is still the cleanest layout.

Deploying with AS3 (optional, for instructors)
----------------------------------------------

Participants build every object through the **UI or CLI** steps in each lab — no
AS3 required. The JSON files under ``configs/`` (``tps-dos-profile.json``,
``bados-profile.json``, ``bot-defense-profile.json``, and the Module 2
``*-policy.json`` files) are **AS3 declarations** kept as an optional shortcut:
an instructor can pre-stage a whole module with one call instead of clicking
through. They are reference/pre-provisioning artifacts, not the participant path.

Deploy one (requires the AS3 RPM installed on the BIG-IP)::

   # POST the declaration to the AS3 endpoint
   curl -sk -u admin:<password> -H "Content-Type: application/json" \
        -X POST https://10.1.1.11/mgmt/shared/appsvcs/declare \
        -d @configs/profiles/bados-profile.json

Then attach the resulting profile/policy to the relevant ``vs-lab-*`` VIP as the
lab describes. If you deploy DoS profiles this way, mind the AS3 shadow-profile
conflict noted above.

Minimal variant
---------------

If you want fewer VIPs, the one split you should *not* collapse is
``vs-lab-dos`` vs ``vs-lab-bot`` (the conflict above). A workable three-VIP
layout merges Modules 1 and 2 onto a single ``vs-lab-rate`` (iRules and LTM
policies coexist fine), keeping ``vs-lab-dos`` and ``vs-lab-bot`` distinct.
