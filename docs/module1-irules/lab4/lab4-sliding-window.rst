Lab 4: Sliding Window Rate Limiter with HTTP 429
=================================================

This lab demonstrates a **sliding window** rate limiter — a more accurate
alternative to the fixed-window approach used in Lab 1. A fixed window resets
its counter at the boundary of each interval, which allows a burst of ``2×
threshold`` requests if timed across a window boundary. The sliding window
only counts requests within the last *N* seconds from *now*, eliminating that
boundary burst.

.. list-table:: Fixed Window vs. Sliding Window
   :header-rows: 1
   :widths: 30 35 35

   * - Property
     - Fixed Window (Lab 1)
     - Sliding Window (Lab 4)
   * - Boundary burst
     - Yes — 2× threshold possible
     - No
   * - Memory per client
     - One counter
     - List of timestamps
   * - Accuracy
     - Approximate
     - Exact
   * - TMM CPU cost
     - Very low
     - Low–medium
   * - Best for
     - High-volume, low-precision
     - Security-sensitive endpoints

.. note::

   This lab must exceed a per-second rate threshold. Ensure the Hackazon container
   is at **full CPU** first — from the Hackazon Web Shell (``10.1.1.5``),
   ``docker update --cpus=0 <hackazon-container>``. A CPU-limited backend caps
   ``ab`` below the threshold so nothing is rejected. See
   :doc:`/setup/lab-topology` (*Backend CPU state*).

Task 1: Upload and Attach the iRule
------------------------------------

#. Navigate to **Local Traffic > iRules > iRule List** and click **Create**.

#. Set the **Name** to ``sliding-window-429``.

#. Paste the contents of ``configs/irules/sliding-window-429.tcl`` into the
   **Definition** field.

   Key parameters:

   .. list-table::
      :header-rows: 1
      :widths: 30 20 50

      * - Variable
        - Default
        - Description
      * - ``static::sw_threshold``
        - 50
        - Max requests in any ``sw_window``-second period
      * - ``static::sw_window``
        - 5
        - Sliding window size in seconds

#. Click **Finished**.

#. Attach ``sliding-window-429`` to **vs-lab-irules**.

Task 2: Observe the Retry-After Response
-----------------------------------------

#. Confirm the sliding-window iRule is the one attached (not a rate-limit iRule
   from an earlier lab)::

      tmsh list ltm virtual vs-lab-irules rules    # expect: rules { sliding-window-429 }

#. Flood the virtual server to exceed the threshold (50 requests in any 5-second
   window). Even the slow backend's ~30 rps clears that (~150 in 5 s)::

      ab -n 200 -c 20 -l http://10.1.10.55/

   Expected: after the first ~50 requests in the window, the rest return **429** —
   shown as ``Non-2xx responses: <N>`` in the ``ab`` summary. *No* ``Non-2xx`` line
   means either the wrong iRule is attached or the rate stayed under 50/5 s.

#. Use ``curl -v`` to inspect the full HTTP 429 response headers::

      curl -v http://10.1.10.55/ 2>&1 | grep -E "< HTTP|< Retry|< X-Rate"

   Expected output::

      < HTTP/1.1 429 Too Many Requests
      < Retry-After: 5
      < X-RateLimit-Limit: 50
      < X-RateLimit-Remaining: 0

Task 3: Demonstrate Boundary Burst Prevention
----------------------------------------------

This task shows that a sliding window blocks the double-burst that is possible
with a fixed window.

#. Temporarily lower the threshold to **5 requests per 5 seconds** by editing
   the iRule::

      set static::sw_threshold 5
      set static::sw_window    5

#. Send 5 requests in rapid succession::

      for i in $(seq 1 5); do curl -so /dev/null -w "%{http_code}\n" http://10.1.10.55/; done

   All 5 return **200**.

#. Immediately (within the same second) send 5 more::

      for i in $(seq 1 5); do curl -so /dev/null -w "%{http_code}\n" http://10.1.10.55/; done

   All 5 return **429** — the sliding window sees 10 requests in the last 5
   seconds, exceeding the threshold of 5.

   .. note::

      **Interpreting the result.** The 200→429 flip *is* the sliding window
      working: both bursts fall inside the trailing 5-second window, so the second
      burst is counted *together with* the first — it inherits the running count
      instead of getting a fresh allowance. That is the boundary-burst defense a
      **fixed** window lacks: a fixed window resets its counter at each boundary,
      so an attacker sending 50 requests at 0:04 and 50 more at 0:06 slips 100
      through in two seconds (two separate windows). The sliding window sees all
      100 within the last 5 s and rejects the overage — you are watching that same
      effect at 5-request scale.

#. **Teardown:** restore the production threshold you lowered for this task::

      set static::sw_threshold 50

   Edit the iRule and click **Update**, so the lab ends at the default 50-per-5 s.

Questions
~~~~~~~~~

- At high request volumes (thousands of clients), the timestamp-list approach
  uses more TMM memory. What is a practical upper bound on clients you would
  apply this iRule to?
- How would you combine this iRule with the per-URI approach from Lab 2 so
  that each endpoint has its own sliding window?
