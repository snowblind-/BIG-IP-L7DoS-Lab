Lab 4: Reject Known-Bad Paths with LTM Policy
==============================================

This lab uses an LTM policy **drop** action to TCP-reset connections to URI
paths that should never receive legitimate traffic — WordPress admin panels,
exposed config files, PHP management interfaces, and common scanner bait.
Because the drop occurs in the LTM policy before the iRule or pool is
consulted, it is extremely lightweight.

.. note::

   This technique is complementary to rate limiting. Rate limiting defends
   against high-volume legitimate-looking traffic; path rejection handles
   requests that are inherently invalid and should never succeed.

Task 1: Create the Reject Policy
---------------------------------

#. Navigate to **Local Traffic > Policies > Policy List** and click
   **Create**.

#. Configure:

   .. list-table::
      :header-rows: 1
      :widths: 30 70

      * - Field
        - Value
      * - Name
        - ``reject-bad-paths-policy``
      * - Strategy
        - ``first-match``
      * - Requires
        - ``http``

#. Add a single rule:

   **Rule 1 — reject-scanner-bait**

   - Condition: **HTTP URI** | **path** | **begins with** (add each entry):

     - ``/wp-admin``
     - ``/wp-login``
     - ``/.env``
     - ``/.git``
     - ``/phpmyadmin``
     - ``/admin/``
     - ``/xmlrpc.php``
     - ``/config.php``

   - Action: **Forward Traffic** | **Reset**

#. Click **Save Draft**, then **Publish**.

Task 2: Attach the Policy to the Virtual Server
------------------------------------------------

#. Navigate to **Local Traffic > Virtual Servers**, click **lab-vs**, and
   select the **Resources** tab.

#. Under **Policies**, click **Manage**.

#. Move ``reject-bad-paths-policy`` to **Enabled**.

   .. important::

      If both ``path-rate-policy`` (Lab 2/3) and ``reject-bad-paths-policy``
      are attached, BIG-IP evaluates them in the order listed. Place the
      reject policy **first** so scanner bait is dropped before the rate
      limiter processes it.

#. Click **Finished**.

Task 3: Test Rejection of Known-Bad Paths
------------------------------------------

#. Attempt to reach a WordPress admin path::

      curl -v http://10.1.10.100/wp-admin/

   Expected result: ``curl: (56) Recv failure: Connection reset by peer``

#. Attempt to reach an exposed config file::

      curl -v http://10.1.10.100/.env

   Expected result: connection reset — no HTTP response.

#. Confirm a legitimate path still works::

      curl -so /dev/null -w "%{http_code}\n" http://10.1.10.100/

   Expected result: **200**

Task 4: Observe in BIG-IP Logs
--------------------------------

#. SSH to the BIG-IP and tail the LTM log while repeating a blocked
   request in a second terminal::

      ssh admin@10.1.1.245 tail -f /var/log/ltm

   Look for entries referencing the reset action from the policy.

#. Alternatively, view policy enforcement in **Statistics > Module
   Statistics > Local Traffic > Policies** to see hit counts per rule.

Task 5: Add a New Blocked Path at Runtime
------------------------------------------

#. Edit the draft policy and add ``/actuator`` (Spring Boot endpoint) to
   the condition values in **Rule 1**.

#. Publish the draft.

#. Test::

      curl -v http://10.1.10.100/actuator/env

   Expected result: connection reset.

Questions
~~~~~~~~~

- Why is TCP reset (``drop``) preferable to responding with HTTP **403** for
  scanner bait paths?
- How would you combine this lab with Module 3 ASM Bot Defense so that
  scanners hitting these paths are also added to a block list?
