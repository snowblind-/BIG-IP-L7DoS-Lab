Module 2: LTM Policy Path-Based Rate Limiting
==============================================

BIG-IP Local Traffic Manager (LTM) policies are declarative rule sets that
match HTTP attributes — URI path, method, headers, cookies — and take
enforcement actions. For rate limiting they offer a middle path between
hand-coded iRules (Module 1) and the full ASM license required for WAF
protection (Module 3).

**How LTM policies work with rate limiting:**

.. code-block:: text

   HTTP Request
       │
       ▼
   LTM Policy (conditions evaluated top-down, first match wins)
       ├── URI starts with /api/login  → insert header X-RateLimit-Profile: strict
       ├── URI starts with /search     → insert header X-RateLimit-Profile: medium
       ├── URI starts with /api/       → insert header X-RateLimit-Profile: medium
       └── default                     → insert header X-RateLimit-Profile: permissive
       │
       ▼
   iRule reads X-RateLimit-Profile and enforces the matching threshold

**Key advantages:**

- Path classification is GUI-manageable without touching iRule code
- A single shared iRule enforces all thresholds — one place to update logic
- Datagroup variant (Lab 3) allows runtime path changes with zero reload
- LTM license only — no ASM required

.. toctree::
   :maxdepth: 1
   :caption: Labs

   lab1/lab1-rate-filter
   lab2/lab2-policy-irule
   lab3/lab3-datagroup
   lab4/lab4-reject-bad-paths
