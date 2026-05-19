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

#. Attach ``concurrent-conn-limit`` to **lab-vs** via the **Resources** tab.

Task 2: Test the Connection Limit
----------------------------------

#. From the attack client, open 30 simultaneous connections to a slow
   endpoint. If no slow endpoint exists, use ``sleep`` to hold connections::

      for i in $(seq 1 30); do
          curl -s --max-time 30 http://10.1.10.100/slow &
      done
      wait

#. In a second terminal, check how many connections BIG-IP is tracking::

      ssh admin@10.1.1.245 \
        "tmsh show sys connection cs-server-addr 10.1.10.100" | wc -l

   The count should not exceed ``static::max_conns`` (20) from the single
   client IP.

#. Attempt a new connection from the same client while the 20 are held::

      curl -v http://10.1.10.100/

   Expected result: the connection is **reset** immediately (TCP RST).

Task 3: Verify Recovery
------------------------

#. Kill the background curl processes::

      kill %1 %2 %3 %4 %5 %6 %7 %8 %9 2>/dev/null; wait

#. Immediately send a new request::

      curl -so /dev/null -w "%{http_code}\n" http://10.1.10.100/

   Expected result: **200** — the connection count drops as clients disconnect,
   and new connections are accepted again.

.. important::

   The ``CLIENT_CLOSED`` event decrements the counter when a connection closes
   cleanly. For abruptly dropped connections (e.g., client crash), BIG-IP's
   TCP half-open timeout will eventually clean up the connection state and
   fire ``CLIENT_CLOSED``.

Questions
~~~~~~~~~

- How does this approach differ from BIG-IP's built-in
  **Connection Rate Limit** on the virtual server?
- What attack type is this *not* effective against, and which iRule lab
  addresses that scenario instead?
