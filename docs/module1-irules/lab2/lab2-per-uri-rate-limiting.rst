Lab 2: Per-URI Rate Limiting
=============================

This lab applies tighter rate limits to specific high-value URI paths —
such as authentication endpoints and search — while leaving general site
traffic unrestricted. URI-specific limits protect expensive or
security-sensitive endpoints without penalizing normal browsing.

.. note::

   This lab must exceed a per-second rate threshold. Ensure the Hackazon container
   is at **full CPU** first — from the Hackazon Web Shell (``10.1.1.5``),
   ``docker update --cpus=0 <hackazon-container>``. A CPU-limited backend caps
   ``ab`` below the threshold so nothing is rejected. See
   :doc:`/setup/lab-topology` (*Backend CPU state*).

Task 1: Upload and Attach the iRule
------------------------------------

#. Navigate to **Local Traffic > iRules > iRule List** and click **Create**.

#. Set the **Name** to ``rate-limit-per-uri``.

#. Paste the contents of ``configs/irules/rate-limit-per-uri.tcl`` into the
   **Definition** field.

   The default protected URIs and thresholds are:

   .. list-table::
      :header-rows: 1
      :widths: 40 30 30

      * - URI Prefix
        - Threshold (req/s)
        - Rationale
      * - ``/search``
        - 20
        - Expensive DB query
      * - ``/user/login``
        - 20
        - Credential-stuffing target

#. Click **Finished**.

#. Navigate to **Local Traffic > Virtual Servers**, click **vs-lab-irules**, select
   the **Resources** tab, click **Manage** under iRules, and add
   ``rate-limit-per-uri`` to **Enabled**.

#. Click **Finished**.

.. note::

   If ``rate-limit-per-ip`` from Lab 1 is still attached, remove it before
   this lab to isolate URI-based behavior.

Task 2: Test an Unprotected Path
---------------------------------

#. Flood the home page — this path is **not** in the protected list::

      ab -n 500 -c 50 http://10.1.10.55/

   Expected result: all requests return **200**. The home page has no
   per-URI limit.

Task 3: Test a Protected Path
-------------------------------

#. First confirm the path returns **200** on a plain GET (so you are testing the
   rate limiter, not a backend error) and that the **per-URI** iRule is the one
   attached::

      curl -si http://10.1.10.55/search | head -1
      tmsh list ltm virtual vs-lab-irules rules     # expect: rules { rate-limit-per-uri }

#. Flood the protected search endpoint (backend at full CPU — see the note at the
   top of the lab)::

      ab -n 400 -c 20 -l http://10.1.10.55/search

   Expected result: the first ~20 requests (the 1-second window) return **200**;
   the rest return **429**, shown as ``Non-2xx responses: <N>`` in the summary.

#. Confirm the unprotected path is still available in the same second::

      curl -so /dev/null -w "%{http_code}\n" http://10.1.10.55/

   Expected result: **200** — the ``/`` path is unaffected.

.. note::

   **Reading the result.** ``Non-2xx responses`` is your 429 count; ~20 requests
   getting **200** is the threshold working. The **body size** is the tell for a
   *real* rate-limit hit — the iRule's 429 is the 38-byte
   ``Rate limit exceeded for this endpoint.`` message. If ``ab`` reports a
   different size (e.g. a 45-byte 404), you are hitting a **backend** response on a
   path that does not exist, not the limiter. ``Failed requests: … (Length: …)`` is
   just the dynamic page varying in size — not real failures (``-l`` silences it).

Task 4: Add a New Protected Path at Runtime
--------------------------------------------

Rather than redeploying the iRule, you can update the ``protected_uris`` list
in the iRule definition.

#. Navigate to **Local Traffic > iRules**, click **rate-limit-per-uri**.

#. Add ``/user/login`` to ``static::protected_uris``::

      set static::protected_uris {
          "/search"
          "/user/login"
      }

#. Click **Update**.

#. Verify the new path is now protected (confirm it is 200 first)::

      curl -si http://10.1.10.55/user/login | head -1
      ab -n 400 -c 20 -l http://10.1.10.55/user/login

.. important::

   Editing an iRule in TMUI causes a brief TMM reload for that rule.
   For production systems with rapidly changing path lists, use the
   LTM Policy + Datagroup approach in **Module 2, Lab 3** instead —
   datagroup edits do not require a rule reload.

Questions
~~~~~~~~~

- What happens if a URI has query parameters (e.g., ``/search?q=test``)? Does
  the rate limit treat ``/search?q=a`` and ``/search?q=b`` as the same key?
- How would you set different thresholds for different paths in the same iRule?
