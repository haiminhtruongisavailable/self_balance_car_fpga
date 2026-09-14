# Rule book: Grok CLI → self-balancing car (handoff)

Same shape as `RULEBOOK-GROK-CLI-TO-D2D.md` on the D2D GEMM hop project. This file is PR / GitHub-Grok handoff only. Student loop lives in `START-HERE.md`.

**Where it lives:** in this folder (and on GitHub if you push). CLI reads it from the tree.

Role split:
- **Grok CLI** = edits RTL / Python logger, then opens or updates a PR (or writes the section-2 block if there is no remote).
- **GitHub Grok / reviewer** = checks the PR against the đồ án goal (FPGA PID balancer, not ESP32).
- The student talks to both. The PR (or section-2 paste) is how CLI keeps the other bot current.

---

## 0. Hard rules for CLI

1. After any meaningful change (PID gains, OFFSET, pin map, logger), **open or update a PR**, or paste the section-2 block. Do not wait for a 200-line UART dump in chat.
2. PR title + body are **structured and short**. No full transcript.
3. Stay in scope: DE0-Nano, `top_module`, GPIO_1/JP2, complementary θ + cascade PID, L298N PWM. No second top. No on-FPGA NN as the inner loop.
4. Never program motors without auto-arm / tilt-kill. KEY[1] is a bench spin test only.
5. Tune from `balance.csv` (mean θ, frac |u| at DUTY_MAX, frac u opposite θ, |θ| p90). One knob per compile when possible.
6. If the student is confused about pose vs θ, stop coding. Point at `az≈1 g` vs `|θ|`.
7. **Fallback:** no GitHub → paste section 2 into the new CLI chat.

---

## 1. When you must open / update a PR

| Trigger | Why |
|--------|-----|
| Gain / OFFSET / AXIS change | Standing zero and stability |
| Pin / qsf change | Harness vs Quartus |
| Logger / UART format | CSV columns |
| Claim “it stands” | Need CSV evidence |

Skip pure comments with zero behavior change.

---

## 2. PR body template (required)

```text
### Balance-car handoff
Goal: <one line>
Layer: RTL PID | IMU filter | pins | logger | other:<name>
Files touched:
- path — <one-line job>
Behavior change:
- <before → after>
Frozen checks (yes/no + clause):
- GPIO_1 / JP2 only:
- OFFSET applied once (theta_i internal):
- KEY[1] is force-PWM not arm:
- L298N IN4 = JP2 pin 13:
Numbers (from balance.csv if run):
- mean θ=… | |θ| p90=… | frac |u|>=DUTY_MAX=… | frac u opposite θ=… | armed=… | killed=…
How to reproduce:
- Quartus top_module.sof
- py log_balance.py COM7 balance.csv
Open risks:
- …
Ask reviewer:
- verify | explain-to-student | gate-scope
```

---

## 3. Success criteria

- Hold upright: LED[4] on, `az~1 g`, `|theta_deg|<15`, `u` not stuck at ±DUTY_MAX.
- Hands-off: does not bang-bang to the other side; p90 |θ| trending down across logs.
- KEY[1]: **both** wheels spin (wiring).
- UART max |uL| matches `DUTY_MAX` in `pid_cascade.v` (if log shows 52 and RTL says 46, `.sof` is stale).

---

## 4. Loop

1. Student asks → CLI edits (one concern).
2. CLI PR or section-2 block.
3. Student compiles, logs CSV, new chat reads `START-HERE.md` + `balance.csv`.
4. Do not keep a 100-turn chat; `/new` + paste `HANDOFF-NEW-CHAT.md`.
