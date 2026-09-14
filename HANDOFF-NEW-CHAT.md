# Paste this as the **first message** after `/new` in Grok CLI

Work only in:

`D:\Projects\Compulsary projects at school\self_balance_car_fpga`

Read `START-HERE.md`, then `PLAN.md`, then `top_module.v`, `pid_cascade.v`, `comp_filter.v`, and `balance.csv` if it exists.

This is a DE0-Nano two-wheel balancer. Top `top_module`, pins GPIO_1/JP2. Inner loop is cascade PID + complementary filter. Do not put a neural net on the FPGA. Do not move pins back to GPIO_2.

**Current job (Phase A then B):** the student must Quartus-compile whatever is on disk so UART `uL` never shows 52 if `DUTY_MAX` is 46. Then tune so the car can be eased off the hands without bang-bang to the other side.

**Last known good physics:** standing `az≈17000` (~1 g), θ a few degrees, LED[4]=armed. KEY[1]=both motors 35% test. IN4=JP2 pin 13.

**Last intended gains (verify in files, not this paragraph):** `STAND_OFFSET=-109` (0.01°), `KP_ANG=26`, `KD_ANG=5`, `DUTY_MAX=46`. If `balance.csv` is newer than this note, trust the CSV.

**How to log:** close PuTTY; `py log_balance.py COM7 balance.csv`; Ctrl+C when done. Analyze the CSV; do not ask the student to paste 50 UART lines.

Stay short. One gain knob per compile. Finish Phase B (hands-off catch).
