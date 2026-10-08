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

   [Clients]                         [BIG-IP VE 17.1.0.1 · mgmt 10.1.1.11]

    kali        10.1.10.100  (.200 = BaDOS attacker)
    win-client  10.1.10.4    (Windows client)
         |
         |  HTTP to the per-module lab VIP:
         |
         +--▶  vs-lab-irules  10.1.10.55   Module 1 · iRules
         +--▶  vs-lab-ltm     10.1.10.56   Module 2 · LTM policies
         +--▶  vs-lab-dos     10.1.10.63   Module 3 · DoS profile
         +--▶  vs-lab-bot     10.1.10.74   Module 3 · Bot Defense
         +--▶  vs_Hackazon_I  10.1.10.61   Module 3.2 · BaDOS demo

    All lab VIPs --▶ Hackazon_pool --▶ Hackazon backend (10.1.20.20)

Each lab targets its own virtual server (see :doc:`setup/lab-topology`), all
fronting the same ``Hackazon_pool``. ``vs_Hackazon_I`` is the blueprint's
prebuilt BaDOS demo VS used by Lab 3.

.. important::

   All attack simulation scripts in this lab are for **authorized lab
   environments only**. Do not execute them against production systems
   or any system you do not own and have explicit written permission to test.

Prerequisites
-------------

- BIG-IP VE 15.1 or later (lab blueprint uses 17.1.0.1)
- ASM / Advanced WAF provisioned (required for Module 3 only)
- TMUI access: ``https://10.1.1.11``
- Web Shell access to the lab instances (UDF UI) — see below
- ``curl`` and ``ab`` (apache2-utils) on the attack client

Accessing the lab environment
-----------------------------

Every instance has a **Web Shell** in the UDF UI that opens a **root** shell
directly. Use it wherever a lab says "SSH to", "run on", or "from" a host
(kali, win-client, the Hackazon/LAMP/ELK servers, the BIG-IP) — no SSH client or
credentials required. For graphical access — the Windows client, or a browser
inside the lab — use the **superjump** host's **Guacamole** interface (RDP to
win-client plus consoles for the other instances).

Management addresses (mgmt subnet ``10.1.1.0/24``):

.. list-table::
   :header-rows: 1
   :widths: 42 22 36

   * - Instance
     - Mgmt IP
     - Access
   * - BIG-IP
     - ``10.1.1.11``
     - TMUI ``https://10.1.1.11`` + Web Shell
   * - kali (attacker)
     - ``10.1.1.7``
     - Web Shell
   * - win-client (good client)
     - ``10.1.1.6``
     - Guacamole (RDP)
   * - Hackazon (Docker backend)
     - ``10.1.1.5``
     - Web Shell
   * - ELK / DVGA (Device ID+ / Kibana)
     - ``10.1.1.10``
     - Web Shell + Kibana
   * - superjump
     - ``10.1.1.8``
     - Guacamole / XRDP

.. toctree::
   :maxdepth: 1
   :caption: Setup

   setup/lab-topology

.. toctree::
   :maxdepth: 2
   :caption: Modules
   :numbered:

   module1-irules/module1
   module2-ltm-policies/module2
   module3-asm-waf/module3

.. toctree::
   :maxdepth: 1
   :caption: Instructor

   answer-key
