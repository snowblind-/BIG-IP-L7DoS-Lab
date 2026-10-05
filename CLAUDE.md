# CLAUDE.md — BIG-IP L7 DoS Lab

Project context for Claude Code. This is an F5 BIG-IP **Layer-7 DoS protection**
hands-on lab (Sphinx docs + iRules/configs/scripts) built on an F5 UDF blueprint.
Read this before editing — it encodes hard-won, environment-specific facts.

## Working conventions
- Docs are **reStructuredText (.rst)** under `docs/` (Sphinx). **Text only — no
  embedded screenshots.** Participant steps are **UI (TMUI) + CLI (tmsh)**; AS3
  JSON under `configs/` is **instructor reference only**, not the participant path.
- After any doc edit, verify the build: `cd docs && sphinx-build -b dummy . /tmp/db`
  — must "succeed" (ignore pre-existing warnings: duplicate labels, html_static_path).
- **Show a diff and wait for approval before editing**; keep changes focused.
- Prefer small, reviewable commits with clear messages; then `git push origin main`.

## Environment / addressing (UDF blueprint)
- **BIG-IP**: mgmt `10.1.1.11`, TMUI `https://10.1.1.11`. Version on box is
  **17.1.1 Build 0.0.6** (docs still carry mixed `17.5`/`17.1.0.1` strings — see
  "Version status").
- **kali** (attacker): mgmt `10.1.1.7`; client `10.1.10.100` (baseline/"good"
  source) + `10.1.10.200` (attacker, bound via `ab -B`). Web Shell opens as root
  in `/root`; demo scripts live in **`/home/ec2-user/`** (`baseline_menu.sh`,
  `AB_DOS.sh`); the repo is cloned to **`/home/ec2-user/lab`** (our scripts under
  `scripts/…`).
- **superjump**: mgmt `10.1.1.8` (no client-subnet NIC). Its **in-browser Firefox**
  (UDF **ACCESS > FIREFOX**) reaches VIPs from a *different source than the
  attacker* — used as the "legitimate client" in two-source demos.
- **win-client**: mgmt `10.1.1.6`, client `10.1.10.4`, server `10.1.20.4`.
- **Hackazon backend**: mgmt `10.1.1.5`, pool member `10.1.20.20`. Runs **Apache
  in a Docker container** (NOT nginx). Access log inside the container:
  `/var/log/apache2/other_vhosts_access.log`. **CPU-limited by default** → slow
  (~20–30 rps ceiling for `ab`). `docker update --cpus=0 <container>` = full speed
  (throughput labs); `docker update --cpus=0.1 <container>` = throttle (stress lab).

## VIPs (client subnet 10.1.10.0/24), pool `Hackazon_pool`
- `vs-lab-irules` `.55` — Module 1 (iRules)
- `vs-lab-ltm` `.56` — Module 2 (LTM policies)
- `vs-lab-dos` `.63` — Module 3 DoS profile labs
- `vs-lab-bot` `.74` — Module 3 bot defense
- `vs_Hackazon_I` `.61` — prebuilt BADoS demo (`Hackazon_BaDOS` profile, XFF-http +
  `XFF_mixed_Attacker_Good` iRule + `L7-DOS_BOT_Logger`); used by Lab 3.

## Module 3 shared-profile model
One shared DoS profile **`lab-dos-tps`** on `vs-lab-dos`; each lab toggles the
detection it needs. Attach the profile **and** a log profile to the **virtual
server** (LTM > Virtual Servers > vs-lab-dos > Security > Policies), NOT to an ASM
security policy. Log profile: `L7-DOS_BOT_Logger` (or `ASM-Bot-DoS-Log-All`) — or
the DoS event log stays empty. Bot lab uses `lab_dos_bot_profile`.

## Hard-won facts / gotchas (do not re-break)
- **Real Hackazon GET-200 paths:** `/`, `/search`, `/user/login`. **Fake (404/302):**
  `/api/login`, `/api/register`, `/checkout`, `/category`, `/product`, `/account`,
  `/cart`, `/slow`. Use only real paths in load tests.
- **Load tool is `ab` only** (no `wrk`). Use `ab -l` (variable length) or the
  dynamic page shows bogus `Failed requests: N (Length)` — not real failures.
  `Non-2xx responses` = the 429s. Warm the backend / `--cpus=0` so `ab` can exceed
  the threshold.
- **TPS thresholds must sit BELOW the achievable rate.** On this slow backend:
  `ip-maximum-tps 5`, `ip-minimum-tps 2`. **TMOS enforces min ≤ max.** And
  **`ip-rate-limiting enabled`** is required (the "By Source IP" toggle) or the
  thresholds silently never evaluate. tmsh keys: `ip-rate-limiting / ip-maximum-tps
  / ip-minimum-tps / ip-tps-increase-rate / ip-request-blocking-mode / mode /
  thresholds-mode`. Run profile-add and log-profile-add on **separate** tmsh lines
  (a chained add aborts on a duplicate-profile error).
- **No Grafana** (it doesn't work in this env). Two native dashboards:
  - **Security > Overview > DoS** → BIG-IP Dashboard, selector **Behavioral DoS**:
    live BADoS/stress (RPS Threshold/Baseline, Server Stress, Concurrent
    Connections, **Protected Applications** Calm/Attack, **Detected Attacks**).
    Used by Labs 2 & 4.
  - **Security > Reporting > DoS > Dashboard** (toggle **Real Time: ON**): attacks
    rollup (Attacks table, Virtual Servers Health, System Health, **Client IP
    Addresses** panel, **Blocked Transactions**). Used by Lab 1.
  - Event log is separate: **Security > Event Logs > DoS > Application Events**.
- DoS profile object lives under **Security > DoS Protection > Protection
  Profiles** (renamed from "DoS Profiles").
- **UDF Web Shell can't detach `screen`** (Ctrl+a d is swallowed). Open **multiple
  Web Shells** (one per long-running stream) instead.
- **Module 1 iRule 429s are `HTTP::respond` (data path) — NOT ASM DoS events.** They
  do not appear in Event Logs > DoS; evidence is the `ab`/curl response + headers.
- Fixed iRule bugs (keep fixed): `concurrent-conn-limit` used `$count` (should be
  `$conns`) + now has self-healing TTLs; `sliding-window-429` had a broken `lsearch`
  eviction that pinned the count at 1 (removed).
- **Two-source validation pattern:** attacker (kali) is blocked/throttled while
  superjump's in-browser Firefox (different source) still loads the app. BADoS
  mitigates **by predicate/signature, not by IP** — the Reporting dashboard records
  all ~26 attacking IPs (incl. the `132.173.99.x` XFF cluster) for attribution, but
  mitigates on request shape. This beats per-IP rate limiting (IP rotation, shared
  NAT, low-and-slow).

## Version status
Box = **17.1.1**. Docs contain stale `17.5` / `17.1.0.1` strings. See
`17.5-upgrade-revalidation.md`. Decide: standardize on **17.1.1** (validated), or
flip to 17.5 only after re-validating the DoS screens (17.1→17.5 has no L7-DoS UI
overhaul per release notes; main risk is `thresholds-mode` flipping auto→manual on
upgrade).

## Status / open items
- Validated live: **Module 1** (all 5 iRule labs) and **Module 3 Lab 1 (TPS)** and
  **Lab 3 (BADoS)**.
- **Module 3 Lab 5 (bot defense) needs review** — known problems to fix.
- Pending: Lab 2 (stress) + Lab 4 (persistent signatures) live validation; Lab 6
  (auto-thresholds); Lab 7 (logs & reports — Lab 1 is the anchor example); the
  auto-threshold relearn (UI) step; version-string standardization.
