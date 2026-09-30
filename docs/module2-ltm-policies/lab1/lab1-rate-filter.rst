Lab 1: Path-Based Rate Filter (Native Traffic Shaping)
=======================================================

This lab uses a BIG-IP **traffic class** (rate filter) applied through an
LTM policy to cap bandwidth on specific URI paths. No iRule code is required.
Enforcement happens in the TMM fast path at the bandwidth level.

.. note::

   Rate filters shape **bandwidth (bps)**, not HTTP request rate (req/s).
   For per-second request limiting, proceed to Lab 2 which combines an LTM
   policy with an iRule.

Task 1: Create Rate Filter Traffic Classes
-------------------------------------------

#. SSH to the BIG-IP::

      ssh admin@10.1.1.11

#. Create three traffic classes representing different protection tiers::

      tmsh create ltm traffic-class rate-filter-strict \
          rate 1mbps burst-size 64kb

      tmsh create ltm traffic-class rate-filter-medium \
          rate 10mbps burst-size 512kb

      tmsh create ltm traffic-class rate-filter-permissive \
          rate 100mbps burst-size 2mb

#. Verify the classes were created::

      tmsh list ltm traffic-class

   Expected output::

      ltm traffic-class rate-filter-medium {
          burst-size 512kb
          rate 10mbps
      }
      ltm traffic-class rate-filter-permissive {
          burst-size 2mb
          rate 100mbps
      }
      ltm traffic-class rate-filter-strict {
          burst-size 64kb
          rate 1mbps
      }

Task 2: Create the LTM Policy
------------------------------

#. In the BIG-IP TMUI, navigate to **Local Traffic > Policies > Policy List**.

#. Click **Create**.

#. Set the following:

   .. list-table::
      :header-rows: 1
      :widths: 30 70

      * - Field
        - Value
      * - Name
        - ``path-rate-filter-policy``
      * - Strategy
        - ``first-match``
      * - Requires
        - ``http``

#. Under **Rules**, click **Add Rule**.

#. Create the following rules in order:

   **Rule 1 — Strict paths**

   - Name: ``strict-paths``
   - Condition: **HTTP URI** | **path** | **begins with** | ``/user/login``
   - Action: **Traffic Rate Limiting** | ``rate-filter-strict``

   **Rule 2 — Medium paths**

   - Name: ``medium-paths``
   - Condition: **HTTP URI** | **path** | **begins with** | ``/search``
   - Action: **Traffic Rate Limiting** | ``rate-filter-medium``

   **Rule 3 — Default**

   - Name: ``default-permissive``
   - Condition: *(none — matches all remaining traffic)*
   - Action: **Traffic Rate Limiting** | ``rate-filter-permissive``

#. Click **Save Draft**, then **Publish**.

Task 3: Attach the Policy to the Virtual Server
------------------------------------------------

#. Navigate to **Local Traffic > Virtual Servers** and click **vs-lab-ltm**.

#. Select the **Resources** tab.

#. Under **Policies**, click **Manage**.

#. Move ``path-rate-filter-policy`` from **Available** to **Enabled**.

#. Click **Finished**.

Task 4: Test Bandwidth Shaping
--------------------------------

#. From the attack client, download via the **strict** path and observe the
   capped transfer rate::

      curl -o /dev/null -w "strict: %{speed_download} bytes/s\n" http://10.1.10.56/user/login

   The transfer is shaped down toward **1 Mbps**.

#. Download via the **permissive** path::

      curl -o /dev/null -w "permissive: %{speed_download} bytes/s\n" http://10.1.10.56/

   Expected: significantly faster (**up to 100 Mbps**).

   .. note::

      Hackazon's pages are small (tens of KB), so the cap is clearest on a larger
      asset or a looped/sustained transfer. If your build serves a large static
      file (a product image or JS bundle), download that via each path for a
      sharper contrast.

.. important::

   Rate filters shape the data stream — they do not drop or reset connections.
   A client hitting the bandwidth limit will experience slower downloads, not
   a connection error. For HTTP 429 rejection semantics, use Lab 2 instead.

Questions
~~~~~~~~~

- In what scenarios is bandwidth shaping preferable to request-rate limiting?
- How would you adjust burst size to allow short bursts while still enforcing
  a sustained rate limit?
