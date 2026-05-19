# BIG-IP L7DoS Lab Overview

This lab demonstrates two primary methods for mitigating Layer 7 Denial of Service (L7DoS) and HTTP rate limiting on F5 BIG-IP:

| Method | Module | Best For |
|--------|--------|----------|
| iRules | LTM | Custom, granular, per-rule logic without ASM license |
| ASM / Advanced WAF | ASM | Policy-driven, behavioral, ML-based detection at scale |

## Lab Scenarios

### Module 1 — iRules Rate Limiting
| Scenario | Description |
|----------|-------------|
| 1.1 | Per-IP HTTP request rate limiting using `table` |
| 1.2 | Per-URI rate limiting (protect specific endpoints) |
| 1.3 | Concurrent connection limiting per client |
| 1.4 | Sliding window rate limiter with HTTP 429 response |

### Module 2 — ASM / Advanced WAF DoS Protection
| Scenario | Description |
|----------|-------------|
| 2.1 | TPS-based DoS profile (by URL and by source IP) |
| 2.2 | Behavioral DoS (BADoS) — anomaly detection |
| 2.3 | Proactive Bot Defense + JS challenge |
| 2.4 | Stress-based detection with server health signal |

## Lab Environment

```
[Attack Client]
      |
      | HTTP/HTTPS
      v
[BIG-IP VE]
  - Virtual Server: 10.1.10.100:443
  - Pool: web-pool → 10.1.20.10:80
      |
      v
[Web Server (target)]
```

## Prerequisites

- BIG-IP VE 15.1+ with ASM provisioned
- Access to TMUI (https://10.1.1.245) and SSH
- `curl` or `wrk`/`ab` on the attack client for traffic generation
