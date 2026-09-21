Lab Setup: Topology and Virtual Servers
========================================

Each protection method in this guide is demonstrated on its **own virtual
server**, all fronting the same Hackazon backend. Using separate VIPs keeps the
methods from interfering with one another and lets you run them side by side
against the same attack — and it is required for Bot Defense, where an AS3 DoS
profile's auto-generated shadow bot profile would otherwise collide with the
standalone Bot Defense profile on the same VS.

Topology
--------

.. code-block:: text

   [Attack Client]                     [BIG-IP VE 17.1.0.1]                [Backend]
    kali 10.1.10.100 ───HTTP──▶  vs-lab-irules  10.1.10.61:80 ─┐
                                 vs-lab-ltm     10.1.10.62:80 ─┤
                                 vs-lab-dos     10.1.10.63:80 ─┼─▶ hackazon-pool
                                 vs-lab-bot     10.1.10.65:80 ─┘     10.1.20.5:80
                                 mgmt 10.1.1.11

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
     - ``10.1.10.61:80``
     - Module 1 — iRule rate limiting (1.1–1.5)
     - The iRule under test (``rate-limit-per-ip``, ``rate-limit-per-uri``,
       ``concurrent-conn-limit``, ``sliding-window-429``,
       ``custom-l7dos-signature``)
   * - ``vs-lab-ltm``
     - ``10.1.10.62:80``
     - Module 2 — LTM policies (2.1–2.4)
     - The LTM policy under test, plus ``policy-triggered-rate-limit`` where the
       scenario uses it
   * - ``vs-lab-dos``
     - ``10.1.10.63:80``
     - Module 3 — DoS profile: TPS (3.1), BADoS (3.2), stress (3.4), and the
       DoS-profile Proactive Bot Defense (3.3, Task 1)
     - ``lab_dos_*`` DoS profile (``tps-dos-profile.json`` /
       ``bados-profile.json`` / ``bot-defense-profile.json``)
   * - ``vs-lab-bot``
     - ``10.1.10.65:80``
     - Module 3 — standalone Bot Defense profile (3.3, Task 2+): verify
       before/after, per-bot rate limits
     - ``security bot-defense profile lab-bot-defense``
       (``bot-defense-standalone.conf``)

All four VIPs share one pool, so the application under test is identical across
methods.

Create the pool and virtual servers
-----------------------------------

Run once on the BIG-IP (``mgmt 10.1.1.11``). Adjust the VIP addresses if your UDF
deployment assigns different ones from the client-subnet range, and rename the
virtual servers if UDF pre-creates any.

.. code-block:: bash

   # Shared backend pool -> Hackazon
   tmsh create ltm pool hackazon-pool members add { 10.1.20.5:80 }

   # One virtual server per method family, all fronting the same pool.
   # SNAT automap so the backend returns via the BIG-IP server-side self IP.
   tmsh create ltm virtual vs-lab-irules destination 10.1.10.61:80 \
       ip-protocol tcp pool hackazon-pool \
       profiles add { http } source-address-translation { type automap }

   tmsh create ltm virtual vs-lab-ltm destination 10.1.10.62:80 \
       ip-protocol tcp pool hackazon-pool \
       profiles add { http } source-address-translation { type automap }

   tmsh create ltm virtual vs-lab-dos destination 10.1.10.63:80 \
       ip-protocol tcp pool hackazon-pool \
       profiles add { http } source-address-translation { type automap }

   tmsh create ltm virtual vs-lab-bot destination 10.1.10.65:80 \
       ip-protocol tcp pool hackazon-pool \
       profiles add { http } source-address-translation { type automap }

   tmsh save sys config

Verify::

   tmsh list ltm virtual one-line | grep vs-lab-
   for ip in 61 62 63 65; do
       curl -s -o /dev/null -w "vs .$ip -> %{http_code}\n" http://10.1.10.$ip/
   done

Each VIP should return the Hackazon application (``200``) before any mitigation
is attached.

.. note::

   Attach only the method being demonstrated to its VIP, and leave the others
   clean. That way a single ``curl`` from kali (``10.1.10.100``) shows exactly
   one mitigation at a time, and you can A/B two methods by changing only the
   destination port-less address (``.61`` vs ``.63``, etc.).

.. important::

   Keep ``vs-lab-dos`` and ``vs-lab-bot`` separate. Binding a standalone Bot
   Defense profile to a virtual server that already carries an AS3-managed DoS
   profile triggers a duplicate-profile error, because AS3 auto-generates a
   shadow ``f5_appsvcs_<dos-profile>_botDefense`` profile. Splitting them across
   two VIPs avoids the conflict entirely.

Minimal variant
---------------

If you want fewer VIPs, the one split you should *not* collapse is
``vs-lab-dos`` vs ``vs-lab-bot`` (the conflict above). A workable three-VIP
layout merges Modules 1 and 2 onto a single ``vs-lab-rate`` (iRules and LTM
policies coexist fine), keeping ``vs-lab-dos`` and ``vs-lab-bot`` distinct.
