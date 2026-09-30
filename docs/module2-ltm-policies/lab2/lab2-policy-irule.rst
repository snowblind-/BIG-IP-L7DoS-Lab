Lab 2: Policy-Triggered iRule Event Rate Limiting
==================================================

This lab separates **path classification** (handled by the LTM policy) from
**rate enforcement** (handled by a single shared iRule). The policy inserts an
``X-RateLimit-Profile`` header identifying which tier applies to each request;
the iRule reads that header and enforces the corresponding threshold.

This design means:

- Adding a new protected path = policy edit only (no iRule change)
- Changing a rate limit threshold = iRule edit only (no policy change)

Task 1: Upload the iRule
--------------------------

#. Navigate to **Local Traffic > iRules > iRule List** and click **Create**.

#. Set the **Name** to ``policy-triggered-rate-limit``.

#. Paste the contents of ``configs/irules/policy-triggered-rate-limit.tcl``
   into the **Definition** field.

   Threshold profiles defined in the iRule:

   .. list-table::
      :header-rows: 1
      :widths: 25 25 50

      * - Profile
        - Threshold (req/s)
        - Intended paths
      * - ``strict``
        - 10
        - Login, checkout, password reset
      * - ``medium``
        - 50
        - Search, general API
      * - ``permissive``
        - 200
        - Static content, home page

#. Click **Finished**.

Task 2: Create the LTM Policy
------------------------------

#. Navigate to **Local Traffic > Policies > Policy List** and click
   **Create**.

#. Configure:

   .. list-table::
      :header-rows: 1
      :widths: 30 70

      * - Field
        - Value
      * - Name
        - ``path-rate-policy``
      * - Strategy
        - ``first-match``
      * - Requires
        - ``http``

#. Add the following rules:

   **Rule 1 — strict-paths**

   - Condition: **HTTP URI** | **path** | **begins with** | ``/user/login``
   - Action: **HTTP Header** | **Insert** | Name: ``X-RateLimit-Profile`` |
     Value: ``strict``

   **Rule 2 — medium-paths**

   - Condition: **HTTP URI** | **path** | **begins with** | ``/search``
   - Action: **HTTP Header** | **Insert** | Name: ``X-RateLimit-Profile`` |
     Value: ``medium``

   **Rule 3 — default-permissive**

   - Condition: *(none)*
   - Action: **HTTP Header** | **Insert** | Name: ``X-RateLimit-Profile`` |
     Value: ``permissive``

#. Click **Save Draft**, then **Publish**.

Task 3: Attach Policy and iRule to the Virtual Server
------------------------------------------------------

#. Navigate to **Local Traffic > Virtual Servers**, click **vs-lab-ltm**, and
   select the **Resources** tab.

#. Under **Policies**, click **Manage** and move ``path-rate-policy`` to
   **Enabled**.

#. Under **iRules**, click **Manage** and move
   ``policy-triggered-rate-limit`` to **Enabled**.

   .. important::

      The LTM policy must be evaluated **before** the iRule reads the header.
      BIG-IP evaluates policies before iRules in the ``HTTP_REQUEST`` event by
      default — no additional ordering configuration is needed.

#. Click **Finished**.

Task 4: Test Per-Path Rate Limiting
-------------------------------------

   (Backend at full CPU — see the note at the top of the lab. Confirm each path is
   **200** first with ``curl -si http://10.1.10.56<path> | head -1``.)

#. Test the **strict** profile on the login page (limit: 10 req/s)::

      ab -n 400 -c 20 -l http://10.1.10.56/user/login

   You should see **429** (``Non-2xx``) once the client exceeds 10 req/s — ~10
   pass, the rest are rejected.

#. Test the **medium** profile on search (limit: 50 req/s)::

      ab -n 400 -c 20 -l http://10.1.10.56/search

   Higher throughput is allowed before 429s appear (~50 req/s).

#. Confirm the **permissive** home page is unaffected at moderate rates::

      ab -n 200 -c 20 -l http://10.1.10.56/

   Expected result: all **200** at moderate load (well below the 200 req/s
   permissive limit).

Task 5: Add a New Protected Path Without Editing the iRule
-----------------------------------------------------------

#. Navigate to **Local Traffic > Policies**, click **path-rate-policy**,
   and click **Edit Draft** (or create a new draft).

#. In **Rule 1 (strict-paths)**, add ``/search`` to the condition values.
   Because Rule 1 is evaluated **first** (``first-match``), ``/search`` is now
   classified **strict** instead of medium.

#. Click **Save Draft**, then **Publish**.

#. Verify ``/search`` now trips at the *strict* threshold (10 req/s) — far sooner
   than the medium 50 req/s it hit in Task 4::

      ab -n 400 -c 20 -l http://10.1.10.56/search

   The iRule was not modified — only the policy changed.

Questions
~~~~~~~~~

- The iRule removes the ``X-RateLimit-Profile`` header before forwarding to
  the pool. Why is this important?
- What happens to requests that match no policy rule and no default rule?
  How does the iRule handle a missing or empty header?
