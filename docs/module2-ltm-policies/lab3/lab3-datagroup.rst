Lab 3: Dynamic Path Configuration with Datagroups
==================================================

This lab extends the Lab 2 architecture by storing path-to-profile mappings
in a BIG-IP **internal datagroup** instead of hard-coded policy conditions.
Adding or removing protected paths becomes a single ``tmsh`` command — no
policy edit, no iRule change, and no service interruption.

.. note::

   This is the recommended pattern for environments where the list of
   rate-limited URIs changes frequently (e.g., new API endpoints released
   weekly) or where network operations staff need to respond to an attack
   by adding a path limit without a change control window.

.. note::

   This lab must exceed a per-second rate threshold. Ensure the Hackazon container
   is at **full CPU** first — from the Hackazon Web Shell (``10.1.1.5``),
   ``docker update --cpus=0 <hackazon-container>``. A CPU-limited backend caps
   ``ab`` below the threshold so nothing is rejected. See
   :doc:`/setup/lab-topology` (*Backend CPU state*).

Task 1: Create the Datagroup
-----------------------------

#. SSH to the BIG-IP::

      ssh admin@10.1.1.11

#. Create the datagroup from the lab file::

      tmsh load sys config merge file \
          /shared/tmp/rate-limit-paths.dg

   Alternatively, create it manually::

      tmsh create ltm data-group internal rate_limit_paths \
          type string \
          records add {
              /search      { data "medium" }
          }

#. Verify the datagroup::

      tmsh list ltm data-group internal rate_limit_paths

Task 2: Update the LTM Policy to Use the Datagroup
----------------------------------------------------

#. Navigate to **Local Traffic > Policies**, click **path-rate-policy** from
   Lab 2, and click **Edit Draft**.

#. Replace all three existing rules with a single new rule:

   **Rule 1 — datagroup-match**

   - Condition: **HTTP URI** | **path** | **begins with** |
     **Datagroup:** ``/Common/rate_limit_paths``
   - Action: **HTTP Header** | **Insert** | Name: ``X-RateLimit-Profile`` |
     Value: ``datagroup``

#. Click **Save Draft**, then **Publish**.

   .. note::

      The action value ``datagroup`` is a sentinel telling the iRule to perform
      a second datagroup lookup at request time to resolve the actual profile
      name (``strict``, ``medium``, or ``permissive``). This is handled by the
      ``class match`` call in ``policy-triggered-rate-limit.tcl``.

Task 3: Verify Existing Paths Still Work
-----------------------------------------

#. Test the medium path (backend at full CPU; confirm 200 first with
   ``curl -si http://10.1.10.56/search | head -1``)::

      ab -n 400 -c 20 -l http://10.1.10.56/search

   Expected: **429** (``Non-2xx``) once exceeding 50 req/s.

#. Show that a path **not** in the datagroup is unrestricted — it falls to the
   permissive default::

      ab -n 400 -c 20 -l http://10.1.10.56/user/login

   Expected: all **200** (``/user/login`` isn't in ``rate_limit_paths`` yet).

Task 4: Add a New Path at Runtime Without Any Policy or iRule Change
--------------------------------------------------------------------

#. Add ``/user/login`` to the datagroup as **strict**::

      tmsh modify ltm data-group internal rate_limit_paths \
          records add { /user/login { data "strict" } }

#. Immediately re-test it — no reload required. It is now rate-limited where it
   was unrestricted in Task 3::

      ab -n 400 -c 20 -l http://10.1.10.56/user/login

   Expected: **429** at the strict threshold of 10 req/s.

#. Remove the path when no longer needed::

      tmsh modify ltm data-group internal rate_limit_paths \
          records delete { /user/login }

Task 5: Persist the Datagroup Change
--------------------------------------

#. Save the running config so the change survives a reboot::

      tmsh save sys config

.. important::

   Datagroup modifications take effect immediately in the TMM without a
   sync or reload. However, they must be saved with ``tmsh save sys config``
   and synchronized to standby units in an HA pair with
   ``tmsh run cm config-sync to-group <device-group>``.

Questions
~~~~~~~~~

- How does the ``class match -value $uri starts_with rate_limit_paths``
  call handle URIs that match multiple datagroup entries (e.g., if both a broad
  ``/user`` prefix and a specific ``/user/login`` entry were present)?
- What is the operational trade-off between using a datagroup vs. an external
  data source (like an iControl REST call) to feed the path list?
