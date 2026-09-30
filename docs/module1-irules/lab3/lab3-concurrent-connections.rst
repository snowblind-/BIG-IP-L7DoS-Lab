Lab 3: Concurrent Connection Limiting
======================================

This lab limits the number of simultaneous open TCP connections allowed from
a single client IP. Unlike request-rate limiting (which counts HTTP requests
per second), concurrent connection limiting caps how many connections are open
*at the same time* — effective against slow-connection attacks (e.g.,
Slowloris) and clients that hold connections open.

.. note::

   This iRule uses ``CLIENT_ACCEPTED`` and ``CLIENT_CLOSED`` events, which
   fire at the TCP connection level — before any HTTP request is parsed.
   It works for both HTTP/1.1 and HTTP/2.

Task 1: Upload and Attach the iRule
------------------------------------

#. Navigate to **Local Traffic > iRules > iRule List** and click **Create**.

#. Set the **Name** to ``concurrent-conn-limit``.

#. Paste the contents of ``configs/irules/concurrent-conn-limit.tcl`` into
   the **Definition** field.

   Key parameters:

   .. list-table::
      :header-rows: 1
      :widths: 30 20 50

      * - Variable
        - Default
        - Description
      * - ``static::max_conns``
        - 20
        - Maximum simultaneous connections per client IP

#. Click **Finished**.

#. Attach ``concurrent-conn-limit`` to **vs-lab-irules** via the **Resources** tab.

Task 2: Test the Connection Limit
----------------------------------

#. Confirm the concurrent iRule is the one attached (not a rate-limit iRule from
   an earlier lab)::

      tmsh list ltm virtual vs-lab-irules rules    # expect: rules { concurrent-conn-limit }

#. From the attack client, open 30 simultaneous connections. The home page ``/``
   is served slowly on the lab backend (~1.5 s), so connections stay open long
   enough to build past the limit — no artificial slow endpoint needed::

      for i in $(seq 30); do
          curl -s -o /dev/null -w "%{http_code} " --max-time 30 http://10.1.10.55/ &
      done; wait; echo

   Expected result: about **20** requests print **200** (they got a connection
   slot) and the rest print **000** — curl's code for "no response", i.e. the
   connection was **reset** by the iRule once the client passed 20 concurrent.

#. *(Optional, while a burst is in flight)* check how many connections BIG-IP is
   tracking for the client — it should not exceed ``static::max_conns`` (20)::

      tmsh show sys connection cs-client-addr 10.1.10.100 cs-server-addr 10.1.10.55 | grep -c any

.. note::

   **Reading the results.** ``000`` — and, if you use a plain ``&``/``wait`` loop,
   curl **exit 7** ("couldn't connect") or **exit 56** ("recv failure") — mean the
   connection was **reset by the limiter**: the mitigation working, not an error.
   The ~20 that return **200** are the connections allowed under the cap.

   You can also see the cap in the **timing**: the rejected connections print
   ``000`` almost instantly (reset at connect), while the ~20 allowed ``200``
   responses trickle in over the next ~1.5 s as they finish on the slow backend —
   the split is visible in *when* the codes appear, not just the counts.

Task 3: Verify Recovery
------------------------

#. Once the burst above finishes (``wait`` returns, so every connection has
   closed), send a new request::

      curl -so /dev/null -w "%{http_code}\n" http://10.1.10.55/

   Expected result: **200** — as connections close, ``CLIENT_CLOSED`` decrements
   the counter, so new connections are accepted again.

.. important::

   The ``CLIENT_CLOSED`` event decrements the counter when a connection closes
   cleanly. For abruptly dropped connections (e.g., client crash), BIG-IP's
   TCP half-open timeout will eventually clean up the connection state and
   fire ``CLIENT_CLOSED``. As a safety net, the counter also carries a **60 s idle
   timeout** and a **300 s hard lifetime**, so a stale count self-heals rather
   than permanently rejecting new connections.

Reset and teardown
------------------

#. The counter self-heals — if the client stops connecting, its entry expires
   after the idle timeout (60 s). To clear it immediately, drop the client's
   connections::

      tmsh delete sys connection cs-client-addr 10.1.10.100

#. Restore the virtual server for the next lab by detaching the iRule::

      tmsh modify ltm virtual vs-lab-irules rules none

.. note::

   If a burst ever caps far below 20, the counter is wedged from a prior run —
   wait for the idle timeout, or run the ``delete sys connection`` above. (The
   TTLs above prevent this from persisting.)

Questions
~~~~~~~~~

- How does this approach differ from BIG-IP's built-in
  **Connection Rate Limit** on the virtual server?
- What attack type is this *not* effective against, and which iRule lab
  addresses that scenario instead?
