// =============================================================================
// top_module — DE0-Nano self-balancing car
// Title: FPGA-Based Self-Balancing Car with PID Control and Tuning
//
// GPIO_1 (JP2). KEY[0]=reset. KEY[1]=e-stop.
// Auto-arm ~0.25 s upright. Kill |theta|>45° for 0.2 s. SW[0]=force PWM. SW[1]=INV_U.
// =============================================================================
module top_module (
    input  wire        CLOCK_50,
    input  wire [1:0]  KEY,
    input  wire [3:0]  SW,
    output wire [7:0]  LED,
    inout  wire [12:0] GPIO_1
);

    localparam integer CLK_HZ  = 50_000_000;
    localparam integer POLL_HZ = 200;

    // Sign flips — change these if the car drives the wrong way (see RUN_BALANCE.md)
    localparam INV_THETA = 1'b0;  // 1 = theta sign reversed
    localparam INV_GYRO  = 1'b0;  // 1 = use -gy
    localparam INV_U     = 1'b0;  // 1 = both motors reversed
    localparam INV_L     = 1'b0;  // 1 = left motor reversed
    localparam INV_R     = 1'b0;  // 1 = right motor reversed
    localparam INV_ENC_L = 1'b0;
    localparam INV_ENC_R = 1'b1;  // senior FWD had right encoder counting backward
    // 0=atan2(ax,az)+gy  1=atan2(ay,az)+gx  2=atan2(az,ax)+gy
    localparam integer PITCH_AXIS = 0;  // atan2(ax,az)+gy; log showed ax/gy moving, ay not

    wire rst = ~KEY[0];

    // GPIO_1 JP2: [0]SCL [1]SDA [2]UART_TX [3]ENA [4]ENB [5:8]IN1..IN4
    //             [9:10] enc L A/B  [11:12] enc R A/B
    wire        uart_tx;
    wire        l298n_ena, l298n_enb;
    wire        in1, in2, in3, in4;
    wire        enc_l_a = GPIO_1[9];
    wire        enc_l_b = GPIO_1[10];
    wire        enc_r_a = GPIO_1[11];
    wire        enc_r_b = GPIO_1[12];

    assign GPIO_1[2] = uart_tx;
    assign GPIO_1[3] = l298n_ena;
    assign GPIO_1[4] = l298n_enb;
    assign GPIO_1[5] = in1;
    assign GPIO_1[6] = in2;
    assign GPIO_1[7] = in3;
    assign GPIO_1[8] = in4;

    wire        imu_valid, imu_err;
    wire        imu_dead;
    wire signed [15:0] ax, ay, az, gx, gy, gz;

    mpu6050_reader #(.CLK_HZ(CLK_HZ), .I2C_ADDR(7'h68), .POLL_HZ(POLL_HZ)) u_mpu (
        .clk(CLOCK_50),
        .rst(rst),
        .busy(),
        .sample_valid(imu_valid),
        .error(imu_err),
        .ax(ax), .ay(ay), .az(az),
        .gx(gx), .gy(gy), .gz(gz),
        .scl(GPIO_1[0]),
        .sda(GPIO_1[1])
    );

    // Real MPU always has ~1 g on some axis. All-zero = SDA stuck / wrong JP2 holes.
    assign imu_dead = (ax == 16'sd0) && (ay == 16'sd0) && (az == 16'sd0);

    wire        filt_valid;
    wire signed [15:0] theta_raw, theta_dot_raw;

    // 16:40 mean -5.63°, then 16:47 after trim mean +4.54°. Combined ≈ -1.09°.
    localparam signed [15:0] STAND_OFFSET = -16'sd109;
    comp_filter #(.POLL_HZ(POLL_HZ), .AXIS(PITCH_AXIS), .ALPHA(8'd220), .OFFSET(STAND_OFFSET)) u_filt (
        .clk(CLOCK_50),
        .rst(rst),
        .valid_i(imu_valid),
        .ax(ax), .ay(ay), .az(az),
        .gx(INV_GYRO ? -gx : gx),
        .gy(INV_GYRO ? -gy : gy),
        .gz(gz),
        .valid_o(filt_valid),
        .theta(theta_raw),
        .theta_dot(theta_dot_raw)
    );

    wire signed [15:0] theta     = INV_THETA ? -theta_raw     : theta_raw;
    wire signed [15:0] theta_dot = INV_THETA ? -theta_dot_raw : theta_dot_raw;

    wire signed [31:0] count_l, count_r;

    encoder_quad u_enc_l (
        .clk(CLOCK_50), .rst(rst),
        .a(enc_l_a), .b(enc_l_b), .count(count_l)
    );
    encoder_quad u_enc_r (
        .clk(CLOCK_50), .rst(rst),
        .a(enc_r_a), .b(enc_r_b), .count(count_r)
    );

    function signed [15:0] sat16;
        input signed [31:0] v;
        begin
            if (v > 32'sd32767)
                sat16 = 16'sd32767;
            else if (v < -32'sd32768)
                sat16 = -16'sd32768;
            else
                sat16 = v[15:0];
        end
    endfunction

    function [6:0] abs_duty;
        input signed [15:0] u;
        reg signed [15:0] a;
        begin
            a = u[15] ? -u : u;
            if (a > 16'sd100)
                abs_duty = 7'd100;
            else
                abs_duty = a[6:0];
        end
    endfunction

    reg signed [31:0] prev_l, prev_r;
    reg signed [15:0] v_l, v_r;

    always @(posedge CLOCK_50) begin
        if (rst) begin
            prev_l <= 32'sd0;
            prev_r <= 32'sd0;
            v_l    <= 16'sd0;
            v_r    <= 16'sd0;
        end else if (filt_valid) begin
            v_l    <= INV_ENC_L ? -sat16(count_l - prev_l) : sat16(count_l - prev_l);
            v_r    <= INV_ENC_R ? -sat16(count_r - prev_r) : sat16(count_r - prev_r);
            prev_l <= count_l;
            prev_r <= count_r;
        end
    end

    // KEY[1] held = e-stop (active low button).
    reg key1_s0, key1_s1;
    always @(posedge CLOCK_50) begin
        if (rst) begin
            key1_s0 <= 1'b1;
            key1_s1 <= 1'b1;
        end else begin
            key1_s0 <= KEY[1];
            key1_s1 <= key1_s0;
        end
    end
    // KEY[1] held = force both motors (L298N test). Released = PID.
    wire key1_held = ~key1_s1;
    wire estop     = 1'b0;

    wire signed [15:0] u_l_raw, u_r_raw;
    wire armed, killed;

    pid_cascade u_pid (
        .clk(CLOCK_50),
        .rst(rst),
        .tick(filt_valid),
        .imu_err(imu_dead),
        .estop(estop),
        .theta(theta),
        .theta_dot(theta_dot),
        .v_l(v_l),
        .v_r(v_r),
        .u_l(u_l_raw),
        .u_r(u_r_raw),
        .armed(armed),
        .killed(killed)
    );

    wire inv_u_sw = INV_U ^ SW[1];
    wire signed [15:0] u_l0 = inv_u_sw ? -u_l_raw : u_l_raw;
    wire signed [15:0] u_r0 = inv_u_sw ? -u_r_raw : u_r_raw;
    wire signed [15:0] u_l  = INV_L ? -u_l0    : u_l0;
    wire signed [15:0] u_r  = INV_R ? -u_r0    : u_r0;

    // KEY[1] held or SW[0] ON: both wheels 35% forward (prove L298N).
    wire        force_pwm = key1_held | SW[0];
    wire [6:0]  duty_l    = force_pwm ? 7'd35 : abs_duty(u_l);
    wire [6:0]  duty_r    = force_pwm ? 7'd35 : abs_duty(u_r);

    assign in1 = force_pwm ? 1'b1 : (~u_l[15] & (u_l != 16'sd0));
    assign in2 = force_pwm ? 1'b0 : ( u_l[15] & (u_l != 16'sd0));
    assign in3 = force_pwm ? 1'b1 : (~u_r[15] & (u_r != 16'sd0));
    assign in4 = force_pwm ? 1'b0 : ( u_r[15] & (u_r != 16'sd0));

    pwm1 #(.CLK_HZ(CLK_HZ), .PWM_HZ(1000)) u_pwm_l (
        .clk(CLOCK_50), .rst(rst), .duty_pct(duty_l), .pwm(l298n_ena)
    );
    pwm1 #(.CLK_HZ(CLK_HZ), .PWM_HZ(1000)) u_pwm_r (
        .clk(CLOCK_50), .rst(rst), .duty_pct(duty_r), .pwm(l298n_enb)
    );

    wire       uart_busy, uart_wr;
    wire [7:0] uart_data;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(115200)) u_uart (
        .clk(CLOCK_50), .rst(rst),
        .data(uart_data), .wr(uart_wr), .busy(uart_busy), .tx(uart_tx)
    );

    reg [1:0] skip;
    always @(posedge CLOCK_50) begin
        if (rst)
            skip <= 2'd0;
        else if (filt_valid)
            skip <= skip + 1'b1;
    end

    ascii_sample u_fmt (
        .clk(CLOCK_50),
        .rst(rst),
        .kick(filt_valid & (skip == 2'd0) & ~uart_busy),
        .ax(ax), .ay(ay), .az(az),
        .theta(theta),
        .u_l(force_pwm ? 16'sd40 : u_l),
        .u_r(force_pwm ? 16'sd40 : u_r),
        .armed(armed | force_pwm),
        .killed(killed),
        .uart_wr(uart_wr),
        .uart_data(uart_data),
        .uart_busy(uart_busy),
        .done()
    );

    reg [24:0] hb;
    always @(posedge CLOCK_50)
        hb <= rst ? 25'd0 : hb + 1'b1;

    assign LED[0] = hb[24];
    assign LED[1] = imu_err | imu_dead;
    assign LED[2] = count_l[0];
    assign LED[3] = count_r[0];
    assign LED[4] = armed;
    assign LED[5] = killed;
    assign LED[6] = l298n_ena;
    assign LED[7] = theta[15];

endmodule
