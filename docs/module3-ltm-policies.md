# Module 3 — LTM Policy Path-Based Rate Limiting

LTM (Local Traffic Manager) policies provide a declarative, no-code way to match HTTP traffic conditions and take enforcement actions. For rate limiting, they work in two complementary ways:

1. **Native rate filtering** — policy applies a BIG-IP traffic class (rate filter) to matched paths, shaping bandwidth at the data plane
2. **Policy-triggered iRule events** — policy matches the path and fires a specific iRule event, keeping rate-limiting logic centralized in one iRule while letting the policy drive path selection

This approach sits between iRules (fully custom) and ASM (full license required) — it requires only LTM and gives you path-aware enforcement through a GUI-manageable policy.

---

## How LTM Policies Work

```
HTTP Request
    │
    ▼
LTM Policy (conditions evaluated top-down)
    ├── condition: URI path starts with /api/login  → action: apply rate filter "tight"
    ├── condition: URI path starts with /search     → action: apply rate filter "medium"
    ├── condition: URI path starts with /api/       → action: call iRule event "rate_check"
    └── default                                     → action: forward (no rate limit)
```

Conditions and actions are evaluated in rule order; first match wins.

---

## Scenario 3.1 — Path-Based Rate Filter (Native Traffic Shaping)

**Goal:** Use an LTM policy + BIG-IP rate filter to cap bandwidth/connection rate to specific URI paths without any iRule code.

**How it works:** A `rate-filter` (traffic class) defines a bandwidth ceiling. The LTM policy matches a URI prefix and assigns that traffic class. BIG-IP enforces the ceiling in the TMM fast path.

**Limitation:** Rate filters shape bandwidth (bps/pps), not HTTP request rate (req/s). Use Scenario 3.2 for request-per-second enforcement.

**Steps:**

1. Create rate filters via TMSH (see `configs/policies/rate-filters.sh`)
2. Deploy the LTM policy via AS3 (see `configs/policies/path-rate-policy.json`)
3. Attach policy to virtual server

**Test:**
```bash
# Should be rate-shaped to ~10 Mbps on /downloads/
curl -o /dev/null http://10.1.10.100/downloads/large-file.iso

# /api/ should be shaped to ~1 Mbps
curl -o /dev/null http://10.1.10.100/api/data-export
```

---

## Scenario 3.2 — Policy-Triggered iRule Event Rate Limiting

**Goal:** Use the LTM policy to classify requests by path, then hand off to a single iRule that enforces per-path, per-IP rate limits. Policy handles the "what to protect"; iRule handles the "how."

**How it works:**
- LTM policy sets `[HTTP::header insert "X-RateLimit-Profile" "strict"]` (or uses `USER_DEFINED` event triggers) based on URI match
- A single iRule reads the classification and applies the correct threshold
- Separates policy decisions (path matching) from enforcement logic (rate counting)

**Apply:**
- Policy: `configs/policies/path-rate-policy.json`
- iRule: `configs/irules/policy-triggered-rate-limit.tcl`

**Test:**
```bash
# /api/login — strict profile (10 req/s)
ab -n 100 -c 10 http://10.1.10.100/api/login

# /search — medium profile (50 req/s)
ab -n 100 -c 10 http://10.1.10.100/search

# / — default profile (200 req/s)
ab -n 100 -c 10 http://10.1.10.100/
```

---

## Scenario 3.3 — Policy + Datagroup for Dynamic Path Configuration

**Goal:** Store rate-limited paths and thresholds in a BIG-IP datagroup so they can be updated without modifying the policy or iRule — no config push required.

**How it works:**
- An internal datagroup maps URI prefix → rate limit class name (`strict`, `medium`, `permissive`)
- The LTM policy has a single `datagroup` condition: match URI against the datagroup
- The iRule reads the matched class and applies the corresponding threshold

**Benefits:** Adding or removing protected paths is a datagroup edit — no policy or iRule change, no sync disruption.

**Apply:**
- Datagroup: `configs/policies/rate-limit-paths.dg` (TMSH format)
- Policy: `configs/policies/datagroup-rate-policy.json`
- iRule: `configs/irules/policy-triggered-rate-limit.tcl` (same iRule, reused)

**Update paths at runtime:**
```bash
# Add a new protected path without touching the policy
tmsh modify ltm data-group internal rate_limit_paths records add \
  { /api/new-endpoint { data "strict" } }
```

---

## Scenario 3.4 — Policy Reject Action for Known-Bad Paths

**Goal:** Use LTM policy to immediately TCP-reset or HTTP-reject requests to paths that should never receive traffic (e.g., scanner bait, deprecated endpoints).

**How it works:** Policy condition matches URI; action is `reset` (TCP RST) or `HTTP::respond 403`. No pool hit occurs — enforced entirely in BIG-IP.

**Apply:** `configs/policies/reject-policy.json`

**Test:**
```bash
# Should receive TCP reset or 403
curl -v http://10.1.10.100/wp-admin
curl -v http://10.1.10.100/.env
curl -v http://10.1.10.100/phpmyadmin
```

---

## Comparing LTM Policy Approaches

| | Scenario 3.1 (Rate Filter) | Scenario 3.2 (Policy + iRule) | Scenario 3.3 (Datagroup) |
|-|---------------------------|-------------------------------|--------------------------|
| Enforces req/s | No (bandwidth only) | Yes | Yes |
| Code required | No | iRule | iRule |
| Dynamic path updates | No (policy edit) | No (policy edit) | Yes (datagroup edit) |
| GUI manageable | Yes | Partial | Yes (datagroup UI) |
| Per-IP granularity | No | Yes | Yes |
| LTM license only | Yes | Yes | Yes |

---

## LTM Policy vs. iRules vs. ASM — When to Use Each

| Requirement | Recommended Method |
|-------------|-------------------|
| Simple path-based bandwidth shaping | LTM Policy + Rate Filter |
| Path-aware req/s limiting, no ASM license | LTM Policy + iRule |
| Frequently changing protected paths | LTM Policy + Datagroup + iRule |
| Complex custom logic (headers, cookies, JWTs) | iRule only |
| Behavioral / unknown attack patterns | ASM BADoS |
| Bot mitigation at scale | ASM Bot Defense |
