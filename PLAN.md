# Plan: FPGA self-balancing car (DE0-Nano)

Folder (Windows school):

`D:\Projects\Compulsary projects at school\self_balance_car_fpga`

Linux copy (may lag): `/home/haiminh/self-balance-fpga-de0/`

Do phases in order. Do not add SINDy on the FPGA until Phase 5.

Read `START-HERE.md` first. Handoff: `RULEBOOK-GROK-CLI-TO-BALANCE.md`. New CLI session: paste `HANDOFF-NEW-CHAT.md`.

---

## Frozen object

See `START-HERE.md`. Title: FPGA-Based Self-Balancing Car with PID Control and Tuning.

---

## Done (do not re-litigate)

- GPIO_1 / JP2 pin map vs ESP32 D-labels.
- MPU I2C live (`az~1 g`); encoder LEDs need JP2 pin 29 3.3 V (old ESP32 3V3 hole).
- KEY[1] both-wheel 35% test; IN4 = pin 13 not 11.
- Complementary filter; OFFSET **once** via `theta_i`.
- Auto-arm; tilt-kill; UART hex + `log_balance.py`.
- Standing θ is a **few degrees**, not 90°. A 90° subtract with AXIS=0 made θ≈−95° and permanent kill. Do not put OFFSET back to 9000.

---

## Phase A. Flash the intended `.sof` (now)

RTL on disk (`pid_cascade.v`): `KP_ANG=26`, `KD_ANG=5`, `DUTY_MAX=46`, `DUTY_MIN=10`, `STAND_OFFSET=-109`.

If UART shows `uL=52`, the chip still runs an old max-52 bitstream. Compile and program before any new gain.

Acceptance: log `max(|uL|) <= 46`.

---

## Phase B. Hands-off catch (this week)

From last **saved** CSV (16:55, still 52% firmware): p90 |θ|~22°, 90% of samples at duty ceiling, 33% u opposite θ.

Goal: p90 |θ| < 12°, frac |u| at ceiling < 0.5, frac opposite < 0.25, killed≈0 while trying to stand.

Knobs (one per compile):

| Feel | Change |
|------|--------|
| Weak, falls through | `DUTY_MAX` +4 (cap 50) or `KP_ANG` +2 |
| Slams to other side | `DUTY_MAX` −4 or `KD_ANG` −1 |
| Mean θ not ~0 when holding | `STAND_OFFSET` += 100×mean_θ_deg |

---

## Phase C. Station-keeping

Raise `KP_VEL` only after it can rock in place without dumping. Then heading `KH`.

---

## Phase D. Product

EPCS flash for power-up without PC. 2-pin 3.6–5.7 V. UART optional.

---

## Phase E. Offline “AI” (optional)

`fit_from_csv.py` / SINDy / BO on `balance.csv` to propose OFFSET and PD. Deploy as parameter changes only. No NN in the 200 Hz loop on Cyclone IV.

---

## GitHub Grok bot

Push this folder to GitHub. In the issue/PR, write:

`Read START-HERE.md then RULEBOOK-GROK-CLI-TO-BALANCE.md. Stay in frozen scope.`

Paste the section-2 template from the rule book.
