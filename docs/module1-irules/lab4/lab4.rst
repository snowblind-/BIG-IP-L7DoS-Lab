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

#. Attach ``sliding-window-429`` to **lab-vs**.

Task 2: Observe the Retry-After Response
-----------------------------------------

#. Flood the virtual server to exceed the threshold::

      ab -n 200 -c 20 http://10.1.10.100/

#. Use ``curl -v`` to inspect the full HTTP 429 response headers::

      curl -v http://10.1.10.100/ 2>&1 | grep -E "< HTTP|< Retry|< X-Rate"

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

      for i in $(seq 1 5); do curl -so /dev/null -w "%{http_code}\n" http://10.1.10.100/; done

   All 5 return **200**.

#. Immediately (within the same second) send 5 more::

      for i in $(seq 1 5); do curl -so /dev/null -w "%{http_code}\n" http://10.1.10.100/; done

   All 5 return **429** — the sliding window sees 10 requests in the last 5
   seconds, exceeding the threshold of 5.

   .. note::

      With a fixed-window iRule, the second burst of 5 *could* succeed if
      sent just after a window boundary, because the counter would have just
      reset to zero.

Questions
~~~~~~~~~

- At high request volumes (thousands of clients), the timestamp-list approach
  uses more TMM memory. What is a practical upper bound on clients you would
  apply this iRule to?
- How would you combine this iRule with the per-URI approach from Lab 2 so
  that each endpoint has its own sliding window?
