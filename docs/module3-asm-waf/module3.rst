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

.. toctree::
   :maxdepth: 1
   :caption: Labs

   lab1/lab1
   lab2/lab2
   lab3/lab3
   lab4/lab4
