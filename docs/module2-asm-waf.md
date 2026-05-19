# Module 2 — ASM / Advanced WAF DoS Protection

ASM's DoS protection operates at the policy level and integrates with BIG-IP's analytics engine. It offers three detection modes that can be used independently or combined.

---

## DoS Detection Modes

| Mode | Trigger | Action |
|------|---------|--------|
| TPS-based | Request rate exceeds threshold | Block, CAPTCHA, or JS challenge per source/URL |
| Behavioral (BADoS) | Anomalous traffic pattern vs. learned baseline | Automatic mitigation, rate shaping |
| Stress-based | Server response latency / error rate degrades | Slow down or block sources causing stress |

---

## Scenario 2.1 — TPS-Based DoS Profile

**Goal:** Configure explicit transactions-per-second thresholds and observe blocking when exceeded.

**Steps:**

1. In TMUI, go to **Security > DoS Protection > DoS Profiles**
2. Create a new profile: `lab-dos-tps`
3. Under **Application**, enable **TPS-based Detection**
4. Set thresholds:
   - Detection Criteria: `By Source IP`
   - TPS Increased By: `500%`
   - TPS Reached: `100 TPS`
   - Operation: `Block`
5. Attach the profile to your virtual server's security policy

**Apply via AS3:** See `configs/profiles/tps-dos-profile.json`

**Test:**
```bash
# Generate sustained high-rate traffic
wrk -t4 -c100 -d30s http://10.1.10.100/

# Watch DoS events in real time
# Security > Event Logs > DoS > Application Events
```

**Expected result:** Sources exceeding the TPS threshold appear in DoS event log and receive blocking responses.

---

## Scenario 2.2 — Behavioral DoS (BADoS)

**Goal:** Let BADoS learn normal traffic baseline, then trigger an anomaly and observe automatic mitigation.

**Steps:**

1. Create/edit profile `lab-dos-bados`
2. Enable **Behavioral & Stress-based Detection**
3. Set **Operation Mode** to `Blocking`
4. Allow 10–15 minutes of normal traffic for baseline learning (or use the included baseline script)
5. Launch the attack simulation

**Apply via AS3:** See `configs/profiles/bados-profile.json`

**Baseline traffic:**
```bash
scripts/setup/baseline-traffic.sh
```

**Attack simulation (lab only):**
```bash
scripts/attack/http-flood.sh
```

**Observe:**
- **Security > DoS Protection > DoS Overview** — shows current attack status
- **Security > Reporting > DoS > Dashboard** — TPS and mitigation graphs

---

## Scenario 2.3 — Proactive Bot Defense

**Goal:** Demonstrate JavaScript challenge enforcement to separate bots from legitimate browsers.

**Steps:**

1. In your DoS profile, enable **Bot Defense**
2. Set mode to **Proactive**
3. Configure **Browser Challenge** with grace period: `10 seconds`

**Test — legitimate browser:**
Open `http://10.1.10.100/` in a real browser. You should see a brief challenge page, then be forwarded automatically.

**Test — curl (bot):**
```bash
# curl cannot execute JS — will receive challenge and be blocked
curl -v http://10.1.10.100/
```

**Expected result:** curl receives the JS challenge HTML and cannot pass it. Browser users pass transparently.

---

## Scenario 2.4 — Stress-Based Detection

**Goal:** Show how BIG-IP uses server-side health signals (latency, errors) to identify and suppress sources causing server stress.

**Steps:**

1. Enable **Stress-based Detection** in your DoS profile
2. Set **Latency Increase** threshold: `200%`
3. Start the "slow server" simulation: `scripts/attack/slow-server-sim.sh`
4. Send traffic from multiple simulated sources
5. Observe which sources get throttled based on their contribution to server stress

**Key insight:** Unlike TPS-based, stress-based mitigation throttles sources *proportional to the stress they cause*, not just their raw rate — legitimate heavy users are less likely to be caught.

---

## Comparing the Methods

| | iRules | TPS-based | BADoS | Stress-based |
|-|--------|-----------|-------|--------------|
| License required | LTM only | ASM/WAF | ASM/WAF | ASM/WAF |
| Configuration effort | High (code) | Low | Very low | Low |
| Adapts to traffic patterns | No | No | Yes | Yes |
| False positive risk | Low (explicit) | Medium | Low | Low |
| Granularity | Unlimited (code) | Per-URL, per-IP | Automatic | Per-source |
| Best for | Custom logic | Known thresholds | Unknown attacks | Protecting servers |
