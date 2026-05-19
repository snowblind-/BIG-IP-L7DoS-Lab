# Module 1 — iRules Rate Limiting

iRules provide flexible, code-level rate limiting without requiring an ASM license. They run in the LTM data plane and can enforce limits based on IP, URI, headers, or any HTTP attribute.

---

## Scenario 1.1 — Per-IP HTTP Request Rate Limiting

**Goal:** Block clients that exceed N requests per second, returning HTTP 429.

**How it works:** The `table` command stores a request counter per client IP with a TTL. Each request increments the counter; if it exceeds the threshold within the window, BIG-IP responds directly with 429 without forwarding to the pool.

**Apply:** Attach `configs/irules/rate-limit-per-ip.tcl` to your virtual server.

**Test:**
```bash
# Baseline — should succeed
for i in $(seq 1 5); do curl -so /dev/null -w "%{http_code}\n" http://10.1.10.100/; done

# Flood — should trigger 429s after threshold
ab -n 200 -c 10 http://10.1.10.100/
```

**Expected result:** First N requests (default: 100/sec) return 200. Requests exceeding the threshold return 429 until the window resets.

---

## Scenario 1.2 — Per-URI Rate Limiting

**Goal:** Protect specific high-value or expensive endpoints (e.g., `/api/login`, `/search`) with tighter limits than the rest of the site.

**How it works:** Same `table`-based approach, but the key includes the URI so limits are tracked independently per path.

**Apply:** Attach `configs/irules/rate-limit-per-uri.tcl` to your virtual server.

**Test:**
```bash
# Hit a protected endpoint repeatedly
ab -n 100 -c 5 http://10.1.10.100/api/login

# Unprotected endpoint — should not be affected
ab -n 100 -c 5 http://10.1.10.100/
```

---

## Scenario 1.3 — Concurrent Connection Limiting

**Goal:** Cap the number of simultaneous open connections from a single client IP.

**How it works:** Uses `conn_rate` and connection-event iRule events (`CLIENT_CONNECTED` / `CLIENT_CLOSED`) to track open connections per IP in a `table`. Resets on disconnect.

**Apply:** Attach `configs/irules/concurrent-conn-limit.tcl` to your virtual server.

**Test:**
```bash
# Open many simultaneous connections
ab -n 500 -c 50 http://10.1.10.100/slow-endpoint
```

---

## Scenario 1.4 — Sliding Window Rate Limiter with 429

**Goal:** Demonstrate a more accurate sliding-window approach vs. fixed-window, with a proper HTTP 429 response including `Retry-After` header.

**How it works:** Tracks request timestamps in a table list per IP, evicts entries outside the window, and counts remaining entries to determine rate.

**Apply:** Attach `configs/irules/sliding-window-429.tcl` to your virtual server.

**Test:**
```bash
# Should see 429 with Retry-After header
curl -v http://10.1.10.100/ 2>&1 | grep -E "HTTP|Retry-After"
```

---

## Key iRules Commands Reference

| Command | Purpose |
|---------|---------|
| `table set` | Store a value with optional TTL and lifetime |
| `table incr` | Atomically increment a counter |
| `table lookup` | Read a stored value |
| `[IP::client_addr]` | Get client IP |
| `[HTTP::uri]` | Get request URI |
| `HTTP::respond` | Send response directly from BIG-IP (no pool hit) |
