Module 3: ASM / Advanced WAF DoS Protection
============================================

F5 Advanced WAF (formerly ASM) provides three complementary DoS detection
modes that operate at the application layer. Unlike iRules and LTM policies
(Modules 1 and 2), WAF protection requires an **ASM or Advanced WAF license**
but offers behavioral detection that adapts to traffic patterns automatically.

**Detection modes:**

.. list-table::
   :header-rows: 1
   :widths: 20 35 45

   * - Mode
     - Trigger
     - Action
   * - TPS-based
     - Request rate exceeds explicit threshold
     - Block, CAPTCHA, or JS challenge per source/URL
   * - Behavioral (BADoS)
     - Traffic deviates from learned baseline
     - Automatic rate shaping and mitigation
   * - Stress-based
     - Server latency or error rate degrades
     - Throttle sources causing server stress

.. note::

   All three modes can be enabled simultaneously in a single DoS profile.
   BIG-IP applies the most restrictive applicable mitigation when multiple
   modes trigger.

Module 3 uses **vs-lab-dos** (``10.1.10.63``) for the DoS-profile methods
(TPS, BADoS, stress, and the DoS-profile Proactive Bot Defense) and
**vs-lab-bot** (``10.1.10.74``) for the standalone Bot Defense profile. See
:doc:`/setup/lab-topology`.

Before you begin: enable event logging
--------------------------------------

Every lab in this module validates through **Security > Event Logs**, which only
populate if the virtual server has a security log profile. Attach the existing
**L7-DOS_BOT_Logger** profile (it writes DoS-application and Bot Defense events to
the local database) to both Module 3 VIPs before starting.

**CLI**::

   tmsh modify ltm virtual vs-lab-dos security-log-profiles add { L7-DOS_BOT_Logger }
   tmsh modify ltm virtual vs-lab-bot security-log-profiles add { L7-DOS_BOT_Logger }
   tmsh save sys config

**UI:** Local Traffic > Virtual Servers > ``vs-lab-dos`` > **Security > Policies**,
set **Log Profile** to *Enabled*, move **L7-DOS_BOT_Logger** into *Selected*,
**Update**; repeat for ``vs-lab-bot``.

If an Event Log stays empty during a lab, a missing log profile on the VS is the
usual cause.

Before you begin: the DoS dashboards
------------------------------------

Module 3 uses two native DoS dashboards — **no Grafana required**:

- **Security > Overview > DoS** → the **BIG-IP Dashboard** (set the selector to
  **Behavioral DoS**). A live, per-second view of a protected application: RPS
  Threshold vs Baseline, **Server Stress**, Concurrent Connections, the
  **Protected Applications** status (**Calm / Under Attack**), and a **Detected
  Attacks** list. Best for watching Behavioral DoS and stress in real time
  (Labs 2 and 4).
- **Security > Reporting > DoS > Dashboard** → the reporting rollup: the
  **Attacks** table (Attack ID, severity, vector, trigger, mitigation),
  **Virtual Servers Health**, **System Health**, and **DoS Attack IDs** vs
  **Not attacked**. Toggle **Real Time: ON** for a ~10 s live refresh (otherwise
  the historical view lags while the rollup catches up). Best for TPS attack
  events and per-episode/aggregate reporting (Lab 1).

The per-event log is separate: **Security > Event Logs > DoS > Application
Events**.

.. toctree::
   :maxdepth: 1
   :caption: Labs

   lab1/lab1-tps-based
   lab2/lab2-behavioral-dos
   lab3/lab3-bot-defense
   lab4/lab4-stress-based
   lab5/lab5-persistent-signatures
