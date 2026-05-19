Lab 2: Per-URI Rate Limiting
=============================

This lab applies tighter rate limits to specific high-value URI paths —
such as authentication endpoints and search — while leaving general site
traffic unrestricted. URI-specific limits protect expensive or
security-sensitive endpoints without penalizing normal browsing.

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
      * - ``/api/login``
        - 20
        - Credential stuffing target
      * - ``/api/register``
        - 20
        - Account creation abuse
      * - ``/search``
        - 20
        - Expensive DB query
      * - ``/checkout``
        - 20
        - Payment flow abuse

#. Click **Finished**.

#. Navigate to **Local Traffic > Virtual Servers**, click **lab-vs**, select
   the **Resources** tab, click **Manage** under iRules, and add
   ``rate-limit-per-uri`` to **Enabled**.

#. Click **Finished**.

.. note::

   If ``rate-limit-per-ip`` from Lab 1 is still attached, remove it before
   this lab to isolate URI-based behavior.

Task 2: Test an Unprotected Path
---------------------------------

#. Flood the home page — this path is **not** in the protected list::

      ab -n 500 -c 50 http://10.1.10.100/

   Expected result: all requests return **200**. The home page has no
   per-URI limit.

Task 3: Test a Protected Path
-------------------------------

#. Flood the login endpoint::

      ab -n 200 -c 20 http://10.1.10.100/api/login

   Expected result: the first ~20 requests (within the 1-second window) return
   **200**; subsequent requests in the same window return **429**.

#. Confirm the unprotected path is still available in the same second::

      curl -so /dev/null -w "%{http_code}\n" http://10.1.10.100/

   Expected result: **200** — the ``/`` path is unaffected.

Task 4: Add a New Protected Path at Runtime
--------------------------------------------

Rather than redeploying the iRule, you can update the ``protected_uris`` list
in the iRule definition.

#. Navigate to **Local Traffic > iRules**, click **rate-limit-per-uri**.

#. Add ``/api/password-reset`` to ``static::protected_uris``::

      set static::protected_uris {
          "/api/login"
          "/api/register"
          "/search"
          "/checkout"
          "/api/password-reset"
      }

#. Click **Update**.

#. Verify the new path is now protected::

      ab -n 100 -c 20 http://10.1.10.100/api/password-reset

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
