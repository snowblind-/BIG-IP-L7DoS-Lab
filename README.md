# BIG-IP L7 DoS Lab

A lab environment for testing, demonstrating, and analyzing BIG-IP Layer 7 Denial of Service (L7DoS) protection features.

## Lab Overview

This lab covers BIG-IP's L7DoS mitigation capabilities including:

- **Behavioral DoS (BADoS)** — machine-learning based anomaly detection
- **Proactive Bot Defense** — JavaScript challenge / CAPTCHA enforcement
- **TPS-based rate limiting** — per-URL, per-IP, and per-source thresholds
- **Stress-based detection** — server-side health signal integration
- **iRule-based mitigations** — custom enforcement logic

## Directory Structure

```
BIG-IP-L7DoS-Lab/
├── configs/          # BIG-IP AS3 / TMSH config snippets
│   ├── profiles/     # DoS protection profiles
│   ├── policies/     # Local Traffic Policies
│   └── irules/       # Supporting iRules
├── scripts/          # Lab automation and traffic generation
│   ├── attack/       # Simulated attack scripts (authorized lab use only)
│   └── setup/        # Lab environment provisioning
├── docs/             # Lab guides and architecture notes
└── tests/            # Validation and verification scripts
```

## Prerequisites

- BIG-IP 14.1+ (or BIG-IP Next)
- ASM / Advanced WAF license for DoS profiles
- Lab network access configured per `docs/network-topology.md`

## Quick Start

1. Review `docs/lab-setup.md` for environment prerequisites
2. Deploy base config: `configs/profiles/`
3. Run a baseline traffic test: `scripts/setup/baseline-traffic.sh`
4. Trigger a simulated L7DoS event: `scripts/attack/` (lab environment only)
5. Observe mitigation in BIG-IP Analytics / TMUI

## Lab Scenarios

| Scenario | Description | Config |
|----------|-------------|--------|
| 01 | TPS threshold triggers | `configs/profiles/tps-basic.json` |
| 02 | BADoS behavioral detection | `configs/profiles/bados-profile.json` |
| 03 | Proactive Bot Defense | `configs/profiles/bot-defense.json` |
| 04 | Stress-based + server health | `configs/profiles/stress-based.json` |
| 05 | iRule custom enforcement | `configs/irules/` |

## Important Notice

Attack simulation scripts in `scripts/attack/` are for **authorized lab environments only**. Do not run against production systems or systems you do not own and have explicit permission to test.
