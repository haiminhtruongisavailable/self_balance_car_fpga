# Practice: 5 V fan on L298N (ENA + IN1 + IN2) — JP3

**Separate hardware** from the balancer. Quartus **top = `top_l298n_fan`**, not `top_module`.

## Power

| L298N | Goes to |
|--------|---------|
| **Vs** (motor) | **5 V** supply for the fan (not FPGA 3.3 V) |
| **Vss / logic** | 5 V (module jumper often) |
| **GND** | **Common** with DE0-Nano GND and 5 V supply GND |
| OUT1, OUT2 | Fan + and − |
| ENA jumper | **Removed** — FPGA drives ENA |

FPGA USB powers **only** the DE0-Nano. Fan current is from the **5 V** pack/USB-power, through L298N.

L298N drops ~1–2 V, so a 5 V fan may run slow. That is OK for this test.

## FPGA → L298N (JP3 / GPIO_2)

| Function | Verilog | FPGA pin | L298N |
|----------|---------|----------|--------|
| PWM | `GPIO_2[3]` | **PIN_C16** | **ENA** |
| Dir | `GPIO_2[5]` | **PIN_D16** | **IN1** |
| Dir | `GPIO_2[6]` | **PIN_D15** | **IN2** |

Holes: User Manual **Figure 3-10 / 3-12** (JP3 pin 1).

ENB / IN3 / IN4: unused. Leave open or GND.

## UART (PuTTY)

| FPGA | Pin | USB–UART 3.3 V |
|------|-----|----------------|
| TX | `GPIO_2[2]` **PIN_C14** | **RX** |
| RX | `GPIO_2_IN0` **PIN_E15** | **TX** |
| GND | JP3 GND | GND |

Do **not** connect dongle 5 V to the FPGA.

## PuTTY 115200 8N1

| Key | Action |
|-----|--------|
| `0` | stop (0%) |
| `1` | 20% |
| `2` | 40% |
| `3` | 60% |
| `4` | 80% (max in this test) |
| `f` | forward (IN1=1, IN2=0) |
| `r` | reverse (IN1=0, IN2=1) |
| `s` | stop |

Echo of the key comes back on TX.

**LED[0]** = PWM. **LED[1]** = IN1. **LED[2]** = IN2.

## Quartus

Device EP4CE22F17C6. Top **`top_l298n_fan`**.  
Files: `top_l298n_fan.v`, `act/pwm1.v`, `io/uart_rx.v`, `io/uart_tx.v`.  
Pins: `constr/de0_nano_fan.qsf`.

When done, switch top back to **`top_module`**.
