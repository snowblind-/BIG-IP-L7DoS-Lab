# Lab 3 screenshots

Drop these PNGs here (referenced by `.. figure::` directives in
`docs/module3-asm-waf/lab3/lab3-bot-defense.rst`). Until they exist, the Sphinx
build emits "image file not readable" warnings — harmless, but add the files to
clear them.

| Filename | Screen (Security > Bot Defense > Bot Profiles > *lab-bot-defense*) |
|---|---|
| `bot-general-settings.png` | General Settings — name, Enforcement Mode = Blocking, Profile Template = Strict |
| `bot-mitigation-settings.png` | Bot Mitigation Settings — per-class actions + Strict Mitigation Enforcement Cases |
| `bot-browsers.png` | Browsers — Browser Verification = Verify Before Access, Device ID Mode |
| `bot-signature-enforcement.png` | Signature Enforcement — the signature list with Enforce/Stage |
| `bot-whitelist.png` | Whitelist — Source / URL / Mitigation / Challenges entries |

Capture at a readable width; the figures render at 95%.

## Task 5 (search-engine verification + rate limit)

| Filename | Screen |
|---|---|
| `bot-masquerade-blocked.png` | Bot Request: fake Googlebot (unverified IP) → Malicious Bot / Search Engine Verification Failed / Denied |
| `bot-verified-trusted.png` | Bot Request: verified Googlebot → Trusted Bot / Search Engine / Alarm |
| `bot-mitigation-unknown-ratelimit.png` | Bot Mitigation Settings: Unknown = Rate Limit for 5 tps |
| `bot-unknown-ratelimit-denied.png` | Bot Request detail: Configured Rate Limit → Actual TCP Reset → Denied |
