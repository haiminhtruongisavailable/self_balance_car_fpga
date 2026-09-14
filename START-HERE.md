# Start here (self-balancing car, DE0-Nano)

You work this folder one step at a time. Runtime control is cascade PID on the FPGA. Do not replace the inner loop with a neural net. SINDy / BO / Lagrangian stay offline.

## What this robot does

Two-wheel inverted pendulum. Terasic **DE0-Nano** (Cyclone IV E EP4CE22F17C6) replaces the senior ESP32. MPU-6050, L298N, two JGA25-370 motors with Hall encoders.

Each control tick (~200 Hz): complementary θ from `atan2(ax,az)` + `gy`, then cascade PID → PWM on L298N ENA/ENB.

## Grok bot / new CLI read order

1. This file.
2. `HANDOFF-NEW-CHAT.md` (paste into `/new` as the first user message).
3. `PLAN.md` for remaining work.
4. `RULEBOOK-GROK-CLI-TO-BALANCE.md` for PRs / GitHub Grok.
5. `top_module.v` then `pid_cascade.v` then `comp_filter.v`.
6. `balance.csv` if present (latest log).

Do not invent a new IMU bus, a second top, or GPIO_2. Do not arm motors from KEY[1] (that is the 35% hardware test).

## Frozen object (do not grow)

- Board: DE0-Nano, header **JP2 = GPIO_1** (not JP3/GPIO_2, not JP1/GPIO_0).
- Top: `top_module`. Pins: `top_module.qsf`.
- Pitch: `PITCH_AXIS=0` (`atan2(ax,az)` + `gy`). Standing Z-up: `az ≈ 17000` (~1 g), θ a few degrees after trim.
- `STAND_OFFSET` in `top_module.v` is the only IMU zero knob (0.01° units). Last good hold mean was about −5.6° then +4.5° after first trim; combined about **−109**.
- L298N: ENA JP2 pin 6, ENB pin 7, IN1–IN4 pins 8, 9, 10, **13** (skip 11=5 V, 12=GND). Jumpers on ENA/ENB **off**.
- KEY[0]=reset. KEY[1] held = both wheels 35% (wiring test). SW[0]=same force. SW[1]=invert both motors.
- UART 115200: `ax ay az theta uL uR flags` (θ in 0.01°). Log: `py log_balance.py COM7 balance.csv` (close PuTTY first).
- Out of scope on-FPGA: large NN, SINDy solver, BO, Kalman (unless student asks). Offline Python on `balance.csv` is OK.

## Files by job

| File | Job |
|------|-----|
| `top_module.v` | GPIO_1 map, OFFSET, LED, SW/KEY mux |
| `comp_filter.v` | CORDIC + complementary; OFFSET **once** on output (`theta_i` internal) |
| `pid_cascade.v` | Auto-arm, kill, PD+small I, duty min/max, slew |
| `mpu6050_reader.v` / `i2c_master.v` | I2C 50 kHz, 0x68 |
| `pwm1.v` | 1 kHz PWM |
| `encoder_quad.v` | A-rise, B sign |
| `log_balance.py` / `log_balance.bat` | COM → CSV |
| `fit_from_csv.py` | print mean θ and suggested OFFSET |

## Your loop this week (stand the car)

1. Compile `top_module`, program `.sof`. Confirm UART `uL` never exceeds `DUTY_MAX` in `pid_cascade.v` (if you see 52, the new `.sof` is not on the chip).
2. Hold chassis upright, LED[4] stays on, `flags=1`, `az~17000`, `|theta_deg|<15`.
3. Ease off. If it slams to the other side, lower `DUTY_MAX` or `KD_ANG`. If it cannot catch, raise `DUTY_MAX` a little (not back to 52 bang-bang) or `KP_ANG`.
4. One CSV per try. Ctrl+C the logger. Do not paste 200 lines into chat; point at `balance.csv`.

## If a number looks wrong

- `theta_deg ≈ 90` or `−95` with `az≈1 g`: OFFSET applied twice or old `.sof`.
- `theta_deg = −327.68`: 16-bit overflow; `theta_i` must not subtract OFFSET in the loop.
- `ax=ay=az=0`: MPU 3.3 V (JP2 pin 29) missing.
- Only one wheel on KEY[1]: IN4 must be pin **13**, not 11.
- COM Access denied: one owner of COM7 (PuTTY **or** Python).
