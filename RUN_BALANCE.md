# Self-balancing car (DE0-Nano, GPIO_1 / JP2)

From bring-up logs: MPU is live (`az ~ 0x44xx` = 1 g). Pitch is `atan2(ax,az)` + `gy`. Motors do move. The old 35° kill was cutting them after a short try.

## Compile

Top = `top_module`. Program `output_files/top_module.sof`. **SW[0] off** for balance.

## Run

1. Motor battery on L298N **Vs**. FPGA USB or 2-pin 5 V. MPU/encoders on JP2 **3.3 V (pin 29)**.
2. L298N **ENA/ENB jumpers off**.
3. Hold the chassis upright. After ~0.25 s **LED[4] stays on** (`flags=0001`).
4. Set it on the floor and ease your hands off.
5. Fall past ~45° for 0.2 s → LED[5], motors off. Stand it up, it re-arms.
6. KEY[1] = e-stop. KEY[0] = reset.

If it **drives into the fall**, flip **SW[1]** (inverts both motors). No recompile.

SW[0] ON = both wheels 40% forward (L298N test). Turn it **off** to balance.

## UART 115200  `ax ay az theta uL uR flags`

`theta` is 0.01°. `0064` = 1°. `flags` `0001` armed, `0002` killed.

## Gains (`pid_cascade.v`)

| If | Change |
|----|--------|
| Too weak / slow to catch | raise `KP_ANG` (28 → 36) |
| Oscillates | lower `KP_ANG`, raise `KD_ANG` |
| Drives off while upright | raise `KP_VEL` |
| One wheel backward | `INV_L` or `INV_R` in `top_module.v` |

## JP2 holes (same ESP32 wires)

SCL 2, SDA 4, UART TX 5, ENA 6, ENB 7, IN1 8, IN2 9, IN3 10, IN4 13, EncL 14/15, EncR 16/17. 3.3 V = 29. GND = 12 or 30.
