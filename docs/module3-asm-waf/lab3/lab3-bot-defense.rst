Lab 3: Proactive Bot Defense
=============================

Proactive Bot Defense (PBD) injects a JavaScript challenge into HTTP
responses. Legitimate browsers execute the challenge transparently and receive
a cookie that identifies them as real clients for the session. Tools that
cannot execute JavaScript — automated scripts, curl, most bots — fail the
challenge and are blocked.

This lab demonstrates the JS challenge mechanism and compares browser vs.
non-browser behavior.

Task 1: Enable Proactive Bot Defense in the DoS Profile
--------------------------------------------------------

#. Navigate to **Security > DoS Protection > DoS Profiles** and click
   **lab-dos-bados** (or create a new profile ``lab-dos-bot``).

#. Under **Application**, expand **Bot Defense**.

#. Configure:

   .. list-table::
      :header-rows: 1
      :widths: 50 50

      * - Setting
        - Value
      * - Mode
        - Proactive
      * - Browser Challenge Reply Timeout
        - 10 seconds
      * - Allow Browser Access Without Challenge (grace period)
        - 0 seconds
      * - Block Suspicious Browsers
        - Enabled

#. Click **Finished** and apply the policy.

Task 2: Test with a Legitimate Browser
----------------------------------------

#. Open a web browser on any desktop connected to the lab network.

#. Navigate to ``http://10.1.10.100/``.

   You will briefly see a BIG-IP challenge page (typically blank or a
   redirect) while JavaScript executes in the background.

#. The browser automatically passes the challenge and is forwarded to the
   application. This should complete in **under 2 seconds**.

#. Inspect the cookies set by BIG-IP:

   In Chrome: **Developer Tools > Application > Cookies**

   Look for a cookie named ``BIGipServerlab-vs`` or ``TS01...`` — this is
   the bot defense validation cookie. It is presented on subsequent requests
   so the browser is not challenged again.

Task 3: Test with curl (Automated Client)
------------------------------------------

#. From the attack client, send a request with a standard curl user-agent::

      curl -v http://10.1.10.100/ 2>&1 | head -40

   Expected result: you receive the **JavaScript challenge HTML** — not the
   application content. The response body will contain inline JavaScript that
   curl cannot execute.

#. Confirm the response code::

      curl -so /dev/null -w "%{http_code}\n" http://10.1.10.100/

   Expected result: **200** (the challenge page itself is served as 200),
   but the page content is the challenge — not the application.

#. Observe that subsequent curl requests also receive the challenge (curl
   cannot solve it and therefore never receives the validation cookie)::

      for i in $(seq 1 3); do
          curl -so /dev/null -w "%{http_code}\n" -c /tmp/cookies.txt \
               -b /tmp/cookies.txt http://10.1.10.100/
      done

Task 4: Test with a Bot-Like User-Agent
-----------------------------------------

#. Send a request with a known bot user-agent::

      curl -so /dev/null -w "%{http_code}\n" \
           -H "User-Agent: python-requests/2.28.0" \
           http://10.1.10.100/

#. Check the DoS event log for a fingerprint match:

   **Security > Event Logs > DoS > Bot Signatures**

   You should see the request classified as a bot based on the user-agent
   signature.

.. important::

   Proactive Bot Defense introduces a **one-time latency** for new browser
   sessions (the JS challenge round-trip). This is typically 100–500ms.
   Cached challenge cookies eliminate this overhead for returning sessions.
   Evaluate the grace period setting for APIs or mobile apps that cannot
   execute JavaScript — they may need to be allowlisted.

Questions
~~~~~~~~~

- A mobile application using a WebView might fail the JS challenge. How would
  you configure an exception for your mobile app while keeping PBD active for
  all other traffic?
- What is the risk of setting the ``Allow Browser Access Without Challenge``
  grace period to a high value (e.g., 30 seconds)?
