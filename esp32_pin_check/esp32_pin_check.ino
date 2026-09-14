/*
 * ESP32 pin check — senior harness, before FPGA JP3
 *
 * Serial 115200. Unplug the FPGA while this runs (one brain only).
 *
 * Commands (type + Enter):
 *   h     help
 *   0     both motors STOP
 *   1     left  forward
 *   2     left  reverse
 *   3     right forward
 *   4     right reverse
 *   5     both  forward (slow)
 *   p     PWM 0..255  (example: p 80)
 *   e     print encoder counts once
 *   s     toggle live encoder stream
 *   i     I2C scan (MPU often 0x68)
 *   m     read MPU-6050 ax ay az gx gy gz (if 0x68 found)
 *
 * Encoders 34/35/36/39 are input-only (OK).
 * If a motor goes the wrong way, swap that motor's IN pair or OUT wires.
 */

#include <Wire.h>
#include <Arduino.h>

#define ENA    27
#define IN1    13
#define IN2    14
#define ENB    23
#define IN3    18
#define IN4    19

#define ENC_L_A  34
#define ENC_L_B  35
#define ENC_R_A  39
#define ENC_R_B  36

#define I2C_SDA  21
#define I2C_SCL  22

#define PWM_FREQ  1000
#define PWM_RES   8

// analogWrite works on ESP32 Arduino 2.x and 3.x (0..255).
static void pwm_init() {
  pinMode(ENA, OUTPUT);
  pinMode(ENB, OUTPUT);
  analogWrite(ENA, 0);
  analogWrite(ENB, 0);
}

static void pwm_write_left(int duty) {
  analogWrite(ENA, duty);
}

static void pwm_write_right(int duty) {
  analogWrite(ENB, duty);
}

static int pwm_duty = 80;
static volatile int32_t cnt_l = 0;
static volatile int32_t cnt_r = 0;
static bool stream_enc = false;
static uint32_t last_stream_ms = 0;
static int32_t prev_l = 0;
static int32_t prev_r = 0;
static const uint32_t VEL_MS = 200;  // T = 0.2 s

static void IRAM_ATTR isr_l() {
  if (digitalRead(ENC_L_B) == LOW)
    cnt_l++;
  else
    cnt_l--;
}

static void IRAM_ATTR isr_r() {
  if (digitalRead(ENC_R_B) == LOW)
    cnt_r++;
  else
    cnt_r--;
}

static void motors_stop() {
  pwm_write_left(0);
  pwm_write_right(0);
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
  digitalWrite(IN3, LOW);
  digitalWrite(IN4, LOW);
  Serial.println("STOP");
}

static void left_fwd() {
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
  pwm_write_left(pwm_duty);
  Serial.printf("LEFT FWD pwm=%d\n", pwm_duty);
}

static void left_rev() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
  pwm_write_left(pwm_duty);
  Serial.printf("LEFT REV pwm=%d\n", pwm_duty);
}

static void right_fwd() {
  digitalWrite(IN3, HIGH);
  digitalWrite(IN4, LOW);
  pwm_write_right(pwm_duty);
  Serial.printf("RIGHT FWD pwm=%d\n", pwm_duty);
}

static void right_rev() {
  digitalWrite(IN3, LOW);
  digitalWrite(IN4, HIGH);
  pwm_write_right(pwm_duty);
  Serial.printf("RIGHT REV pwm=%d\n", pwm_duty);
}

static void help() {
  Serial.println();
  Serial.println("=== ESP32 pin check (senior map) ===");
  Serial.println("ENA=27 IN1=13 IN2=14 | ENB=23 IN3=18 IN4=19");
  Serial.println("ENC_L 34/35  ENC_R 39/36  I2C SDA=21 SCL=22");
  Serial.println("0 stop | 1 Lfwd 2 Lrev 3 Rfwd 4 Rrev 5 both-fwd");
  Serial.println("p <0-255> pwm | e enc once | s stream enc | i i2c | m mpu");
  Serial.println("Car on blocks. FPGA unplugged. 0 = stop anytime.");
  Serial.println();
}

static void i2c_scan() {
  Serial.println("I2C scan...");
  int n = 0;
  for (uint8_t a = 1; a < 127; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) {
      Serial.printf("  found 0x%02X\n", a);
      n++;
    }
  }
  if (!n)
    Serial.println("  none (check 3.3V SDA SCL GND; MPU AD0=GND -> 0x68)");
}

static void mpu_read() {
  const uint8_t addr = 0x68;
  Wire.beginTransmission(addr);
  Wire.write(0x6B);
  Wire.write(0x00);
  if (Wire.endTransmission() != 0) {
    Serial.println("MPU NACK — not at 0x68 or wrong I2C pins");
    return;
  }
  delay(20);
  Wire.beginTransmission(addr);
  Wire.write(0x3B);
  Wire.endTransmission(false);
  if (Wire.requestFrom((int)addr, 14) != 14) {
    Serial.println("MPU read fail");
    return;
  }
  int16_t ax = (Wire.read() << 8) | Wire.read();
  int16_t ay = (Wire.read() << 8) | Wire.read();
  int16_t az = (Wire.read() << 8) | Wire.read();
  (void)((Wire.read() << 8) | Wire.read());
  int16_t gx = (Wire.read() << 8) | Wire.read();
  int16_t gy = (Wire.read() << 8) | Wire.read();
  int16_t gz = (Wire.read() << 8) | Wire.read();
  Serial.printf("MPU ax=%d ay=%d az=%d gx=%d gy=%d gz=%d\n",
                ax, ay, az, gx, gy, gz);
}

void setup() {
  Serial.begin(115200);
  delay(300);

  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  pinMode(IN3, OUTPUT);
  pinMode(IN4, OUTPUT);
  pwm_init();
  motors_stop();

  pinMode(ENC_L_A, INPUT);
  pinMode(ENC_L_B, INPUT);
  pinMode(ENC_R_A, INPUT);
  pinMode(ENC_R_B, INPUT);
  attachInterrupt(digitalPinToInterrupt(ENC_L_A), isr_l, RISING);
  attachInterrupt(digitalPinToInterrupt(ENC_R_A), isr_r, RISING);

  Wire.begin(I2C_SDA, I2C_SCL);
  help();
}

void loop() {
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line.length() == 0)
      return;
    char c = line.charAt(0);
    if (c == 'h' || c == 'H' || c == '?')
      help();
    else if (c == '0')
      motors_stop();
    else if (c == '1')
      left_fwd();
    else if (c == '2')
      left_rev();
    else if (c == '3')
      right_fwd();
    else if (c == '4')
      right_rev();
    else if (c == '5') {
      left_fwd();
      right_fwd();
    } else if (c == 'p' || c == 'P') {
      int v = line.substring(1).toInt();
      if (v < 0) v = 0;
      if (v > 255) v = 255;
      pwm_duty = v;
      Serial.printf("pwm_duty=%d (next 1-5 uses this)\n", pwm_duty);
    } else if (c == 'e' || c == 'E')
      Serial.printf("enc L=%ld R=%ld\n", (long)cnt_l, (long)cnt_r);
    else if (c == 's' || c == 'S') {
      stream_enc = !stream_enc;
      Serial.printf("stream_enc=%d\n", stream_enc);
    } else if (c == 'i' || c == 'I')
      i2c_scan();
    else if (c == 'm' || c == 'M')
      mpu_read();
    else
      Serial.println("unknown — h for help");
  }

  if (stream_enc && (millis() - last_stream_ms) >= VEL_MS) {
    last_stream_ms = millis();
    int32_t dl = cnt_l - prev_l;
    int32_t dr = cnt_r - prev_r;
    prev_l = cnt_l;
    prev_r = cnt_r;
    /* v_counts_per_sec = dcount / T, T = 0.2 s */
    float vl = dl / 0.2f;
    float vr = dr / 0.2f;
    Serial.printf("count L=%ld R=%ld  dL=%ld dR=%ld  vL=%.1f vR=%.1f counts/s\n",
                  (long)cnt_l, (long)cnt_r, (long)dl, (long)dr, vl, vr);
  }
}
