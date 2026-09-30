Lab 1: Per-IP HTTP Request Rate Limiting
=========================================

This lab demonstrates limiting each client IP to a configurable number of
HTTP requests per second using the BIG-IP ``table`` command. Clients that
exceed the threshold receive an HTTP **429 Too Many Requests** response
directly from BIG-IP — the pool member is never contacted.

Task 1: Upload and Attach the iRule
------------------------------------

#. Log in to the BIG-IP TMUI at ``https://10.1.1.11``.

#. Navigate to **Local Traffic > iRules > iRule List**.

#. Click **Create**.

#. Set the **Name** to ``rate-limit-per-ip``.

#. Paste the contents of ``configs/irules/rate-limit-per-ip.tcl`` into the
   **Definition** field.

   .. code-block:: tcl

      when RULE_INIT {
          set static::rl_threshold 100
          set static::rl_window    1
      }

      when HTTP_REQUEST {
          set client [IP::client_addr]
          set key    "rl_ip_[string map {: _} $client]"

          set count [table incr $key]

          if { $count == 1 } {
              table set $key $count $static::rl_window $static::rl_window
          }

          if { $count > $static::rl_threshold } {
              HTTP::respond 429 content "Rate limit exceeded. Try again later." \
                  "Content-Type" "text/plain" \
                  "Retry-After"  $static::rl_window
              return
          }
      }

#. Click **Finished**.

#. Navigate to **Local Traffic > Virtual Servers** and click **vs-lab-irules**.

#. Select the **Resources** tab.

#. Under **iRules**, click **Manage**.

#. Move ``rate-limit-per-ip`` from **Available** to **Enabled**.

#. Click **Finished**.

.. note::

   The default threshold is **100 requests per second** per client IP.
   To change it, edit ``static::rl_threshold`` in the ``RULE_INIT`` event.

Task 2: Verify Baseline Behavior
---------------------------------

#. SSH to the kali attack client (``10.1.1.7``).

#. Send five sequential requests and confirm all return **200**::

      for i in $(seq 1 5); do
          curl -so /dev/null -w "%{http_code}\n" http://10.1.10.55/
      done

   Expected output::

      200
      200
      200
      200
      200

Task 3: Trigger the Rate Limit
--------------------------------

#. **First ensure the Hackazon backend is at full CPU.** The container is
   CPU-limited by default, which holds ``ab`` to ~30 rps — below the 100 req/s
   limit — so nothing is rejected. On the Hackazon **Web Shell** (``10.1.1.5``)
   remove the limit::

      docker ps                                  # note the Hackazon container
      docker update --cpus=0 <hackazon-container>   # 0 = no CPU limit (full speed)

#. From the attack client, run the flood (``-l`` accepts the variable page length
   so the dynamic body isn't miscounted as failures)::

      ab -n 500 -c 50 -l http://10.1.10.55/

#. Observe the response codes in the ``ab`` summary. You should see a mix of
   **200** (within threshold) and **429** (threshold exceeded) responses.

#. Confirm the BIG-IP absorbed the rejects — the pool member sees far fewer
   requests than ``ab`` sent, because the **429** responses never leave the TMM
   fast path:

   - **(kali)** the ``ab`` summary already shows the split — 200 (passed) vs 429
     (rejected by BIG-IP).
   - **(BIG-IP)** ``tmsh show ltm virtual vs-lab-irules`` — compare the
     client-side vs server-side (pool) counts; the difference is the rejected
     traffic. (Or TMUI: Statistics > Module Statistics > Local Traffic > Virtual
     Servers.)

   The Hackazon backend runs **Apache** in a Docker container on ``10.1.1.5``, so
   there is no ``/var/log/nginx/`` on the host. To watch backend requests
   directly, open the Hackazon **Web Shell** and tail its access log::

      tail -20 /var/log/apache2/other_vhosts_access.log

   If that log lives inside the container rather than on the host, locate it with
   ``docker ps`` then ``docker exec -it <hackazon-container> tail -20
   /var/log/apache2/other_vhosts_access.log``.

Interpreting the ``ab`` output
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A successful run (full-CPU backend) looks like this::

   Concurrency Level:      50
   Time taken for tests:   3.126 seconds
   Complete requests:      500
   Failed requests:        499
      (Connect: 0, Receive: 0, Length: 499, Exceptions: 0)
   Non-2xx responses:      400
   Requests per second:    159.96 [#/sec] (mean)
   ...
   Percentage of the requests served within a certain time (ms)
     50%      1
     90%   1497
    100%   1762 (longest request)

Read it like this:

- **Non-2xx responses: 400** — the rate limit working: 400 requests got **429**
  (rejected), 100 got **200** (within the 100 req/s window). *No* ``Non-2xx`` line
  means the limit never tripped — the backend was still CPU-limited and ``ab``
  stayed under 100 rps; run ``docker update --cpus=0`` on the container and re-run.
- **Failed requests: 499 (Length: 499)** — **not** failures or blocks. ``ab`` flags
  every response whose body length differs from the first; the 200s are the ~64 KB
  page and the 429s are a tiny message, so lengths vary. ``-l`` silences it — all
  are real 200/429 responses.
- **The percentile split is the proof the 429s never touch the backend:** 50% of
  requests finished in **1 ms** (the 429s, answered in the TMM fast path) while 90%
  took **~1.5 s** (the 200s that reached the Hackazon container).
- **159.96 rps** — the achieved rate this run, above the 100/s threshold, which is
  why the 429s appeared.

.. important::

   All **429** responses are generated by BIG-IP in the TMM fast path.
   They consume no pool member resources — the server never sees rejected
   requests.

Task 4: Observe the Rate Limit Reset
--------------------------------------

#. After the flood, wait **two seconds** and send five more requests::

      sleep 2
      for i in $(seq 1 5); do
          curl -so /dev/null -w "%{http_code}\n" http://10.1.10.55/
      done

   Expected output::

      200
      200
      200
      200
      200

   The table entry TTL has expired, resetting the counter to zero.

Questions
~~~~~~~~~

- What would happen to legitimate users behind a shared NAT IP (e.g., a
  corporate proxy) with 100+ employees browsing simultaneously?
- How would you modify the iRule to issue a warning header at 80% of the
  threshold before blocking?
- Why is ``table incr`` used instead of a ``table lookup`` + ``table set``
  sequence?
