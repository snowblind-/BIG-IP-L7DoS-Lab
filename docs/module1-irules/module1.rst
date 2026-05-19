Module 1: iRules Rate Limiting
==============================

iRules provide flexible, code-level rate limiting that runs in the BIG-IP LTM
data plane. Because enforcement happens inside BIG-IP's TMM (Traffic Management
Microkernel), rejected requests never reach the pool — protecting both the
application servers and the connection table.

**Key advantages of iRules for rate limiting:**

- No ASM license required — LTM only
- Unlimited granularity: match on IP, URI, headers, cookies, JWT claims, or
  any combination
- Respond directly with HTTP 429 and standard ``Retry-After`` headers
- Per-rule thresholds independent of other virtual servers

**When to prefer a different method:**

- If protected paths change frequently → use LTM Policy + Datagroup (Module 2)
- If behavioral/unknown attack patterns are the concern → use ASM BADoS (Module 3)
- If a no-code GUI-driven approach is required → use LTM Policies (Module 2)

.. toctree::
   :maxdepth: 1
   :caption: Labs

   lab1/lab1
   lab2/lab2
   lab3/lab3
   lab4/lab4
