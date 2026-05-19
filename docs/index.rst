BIG-IP L7DoS Lab
================

This lab demonstrates three methods for mitigating Layer 7 Denial of Service
(L7DoS) and HTTP rate limiting on F5 BIG-IP, progressing from custom iRule
code through declarative LTM policies to full ASM/Advanced WAF behavioral
protection.

.. list-table::
   :header-rows: 1
   :widths: 10 20 20 50

   * - Module
     - Method
     - License Required
     - Best For
   * - 1
     - iRules
     - LTM
     - Custom, granular, per-rule logic
   * - 2
     - LTM Policies
     - LTM
     - Declarative path-based enforcement without code
   * - 3
     - ASM / Advanced WAF
     - ASM
     - Behavioral, ML-based detection at scale

Lab Environment
---------------

.. code-block:: text

   [Attack Client]  10.1.10.50
         |
         | HTTP / HTTPS
         v
   [BIG-IP VE]      10.1.1.245 (mgmt)
     Virtual Server: 10.1.10.100:80
     Pool:           web-pool → 10.1.20.10:80
         |
         v
   [Web Server]     10.1.20.10

.. important::

   All attack simulation scripts in this lab are for **authorized lab
   environments only**. Do not execute them against production systems
   or any system you do not own and have explicit written permission to test.

Prerequisites
-------------

- BIG-IP VE 15.1 or later
- ASM / Advanced WAF provisioned (required for Module 3 only)
- TMUI access: ``https://10.1.1.245``
- SSH access to BIG-IP and the attack client
- ``curl``, ``ab`` (apache2-utils), or ``wrk`` on the attack client

.. toctree::
   :maxdepth: 2
   :caption: Modules
   :numbered:

   module1-irules/module1
   module2-ltm-policies/module2
   module3-asm-waf/module3
