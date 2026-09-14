// Cascade PID. Inner angle PD (+ small I). Outer velocity P (station-keeping).
// theta / theta_dot: 0.01 deg, 0.01 deg/s.  u: signed duty percent.
module pid_cascade #(
    parameter integer SHIFT = 8,
    parameter signed [15:0] KP_ANG = 16'sd26,
    parameter signed [15:0] KI_ANG = 16'sd1,
    parameter signed [15:0] KD_ANG = 16'sd5,
    parameter signed [15:0] KP_VEL = 16'sd3,
    parameter signed [15:0] KI_VEL = 16'sd0,
    parameter signed [15:0] KH     = 16'sd0,
    parameter signed [15:0] THETA_KILL    = 16'sd4500,
    parameter signed [15:0] THETA_ARM     = 16'sd3000,
    parameter integer       ARM_TICKS     = 5,
    parameter integer       KILL_TICKS    = 20,
    parameter signed [15:0] THETA_REF_LIM = 16'sd1200,
    parameter signed [15:0] IANG_LIM      = 16'sd4000,
    parameter signed [15:0] IVEL_LIM      = 16'sd2000,
    parameter integer       DUTY_MAX      = 46,
    parameter integer       DUTY_MIN      = 10
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick,
    input  wire        imu_err,
    input  wire        estop,
    input  wire signed [15:0] theta,
    input  wire signed [15:0] theta_dot,
    input  wire signed [15:0] v_l,
    input  wire signed [15:0] v_r,
    output reg  signed [15:0] u_l,
    output reg  signed [15:0] u_r,
    output reg         armed,
    output reg         killed
);
    localparam signed [15:0] UMAX = DUTY_MAX;
    localparam signed [15:0] UMIN = DUTY_MIN;

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

    function signed [15:0] clamp;
        input signed [15:0] v;
        input signed [15:0] lim;
        begin
            if (v > lim)
                clamp = lim;
            else if (v < -lim)
                clamp = -lim;
            else
                clamp = v;
        end
    endfunction

    function signed [15:0] abs16;
        input signed [15:0] v;
        begin
            if (v == 16'sh8000)
                abs16 = 16'sd32767;
            else
                abs16 = v[15] ? -v : v;
        end
    endfunction

    // L298N often ignores PWM below ~15%. Boost small nonzero commands.
    function signed [15:0] with_min;
        input signed [15:0] u;
        begin
            if (u == 16'sd0)
                with_min = 16'sd0;
            else if (!u[15] && (u < UMIN))
                with_min = UMIN;
            else if (u[15] && (u > -UMIN))
                with_min = -UMIN;
            else
                with_min = u;
        end
    endfunction

    reg signed [31:0] i_ang;
    reg signed [31:0] i_vel;
    reg [7:0]         up_cnt;
    reg [7:0]         kill_cnt;

    wire signed [15:0] v_mean = sat16(($signed({{16{v_l[15]}}, v_l}) + $signed({{16{v_r[15]}}, v_r})) >>> 1);
    wire signed [15:0] v_diff = sat16($signed({{16{v_l[15]}}, v_l}) - $signed({{16{v_r[15]}}, v_r}));

    wire tilt_kill = (abs16(theta) > THETA_KILL) | imu_err;
    wire can_arm   = (abs16(theta) < THETA_ARM);

    wire signed [15:0] e_v = -v_mean;

    wire signed [31:0] th_ref_w =
        ($signed({{16{KP_VEL[15]}}, KP_VEL}) * $signed({{16{e_v[15]}}, e_v})
       + $signed({{16{KI_VEL[15]}}, KI_VEL}) * i_vel) >>> SHIFT;

    wire signed [15:0] theta_ref = clamp(sat16(th_ref_w), THETA_REF_LIM);
    wire signed [15:0] e_a       = theta - theta_ref;

    wire signed [31:0] u_w =
        ($signed({{16{KP_ANG[15]}}, KP_ANG}) * $signed({{16{e_a[15]}}, e_a})
       + $signed({{16{KI_ANG[15]}}, KI_ANG}) * i_ang
       + $signed({{16{KD_ANG[15]}}, KD_ANG}) * $signed({{16{theta_dot[15]}}, theta_dot})) >>> SHIFT;

    wire quiet = (abs16(e_a) < 16'sd30) && (abs16(theta_dot) < 16'sd200);
    wire signed [15:0] u_sat = quiet ? 16'sd0 : with_min(clamp(sat16(u_w), UMAX));

    wire signed [31:0] h_w = ($signed({{16{KH[15]}}, KH}) * $signed({{16{v_diff[15]}}, v_diff})) >>> SHIFT;
    wire signed [15:0] h   = sat16(h_w);

    wire signed [15:0] ul_w = clamp(sat16($signed({{16{u_sat[15]}}, u_sat}) - $signed({{16{h[15]}}, h})), UMAX);
    wire signed [15:0] ur_w = clamp(sat16($signed({{16{u_sat[15]}}, u_sat}) + $signed({{16{h[15]}}, h})), UMAX);

    wire sat_u = (abs16(u_sat) >= UMAX);

    always @(posedge clk) begin
        if (rst) begin
            armed    <= 1'b0;
            killed   <= 1'b0;
            i_ang    <= 32'sd0;
            i_vel    <= 32'sd0;
            up_cnt   <= 8'd0;
            kill_cnt <= 8'd0;
            u_l      <= 16'sd0;
            u_r      <= 16'sd0;
        end else begin
            if (estop) begin
                armed    <= 1'b0;
                killed   <= 1'b0;
                up_cnt   <= 8'd0;
                kill_cnt <= 8'd0;
            end else if (tick) begin
                if (tilt_kill) begin
                    if (kill_cnt >= KILL_TICKS[7:0]) begin
                        killed <= 1'b1;
                        armed  <= 1'b0;
                        up_cnt <= 8'd0;
                    end else
                        kill_cnt <= kill_cnt + 8'd1;
                end else begin
                    kill_cnt <= 8'd0;
                    killed   <= 1'b0;
                    if (can_arm) begin
                        if (up_cnt >= ARM_TICKS[7:0])
                            armed <= 1'b1;
                        else
                            up_cnt <= up_cnt + 8'd1;
                    end else
                        up_cnt <= 8'd0;
                end
            end

            if (!armed) begin
                i_ang <= 32'sd0;
                i_vel <= 32'sd0;
                u_l   <= 16'sd0;
                u_r   <= 16'sd0;
            end else if (tick) begin
                if (!sat_u) begin
                    if (i_ang + $signed({{16{e_a[15]}}, e_a}) > {{16{IANG_LIM[15]}}, IANG_LIM})
                        i_ang <= {{16{IANG_LIM[15]}}, IANG_LIM};
                    else if (i_ang + $signed({{16{e_a[15]}}, e_a}) < -{{16{IANG_LIM[15]}}, IANG_LIM})
                        i_ang <= -{{16{IANG_LIM[15]}}, IANG_LIM};
                    else
                        i_ang <= i_ang + $signed({{16{e_a[15]}}, e_a});

                    if (i_vel + $signed({{16{e_v[15]}}, e_v}) > {{16{IVEL_LIM[15]}}, IVEL_LIM})
                        i_vel <= {{16{IVEL_LIM[15]}}, IVEL_LIM};
                    else if (i_vel + $signed({{16{e_v[15]}}, e_v}) < -{{16{IVEL_LIM[15]}}, IVEL_LIM})
                        i_vel <= -{{16{IVEL_LIM[15]}}, IVEL_LIM};
                    else
                        i_vel <= i_vel + $signed({{16{e_v[15]}}, e_v});
                end
                // slew limit so duty cannot jump +max to -max in one sample
                if (ul_w > u_l + 16'sd6)
                    u_l <= u_l + 16'sd6;
                else if (ul_w < u_l - 16'sd6)
                    u_l <= u_l - 16'sd6;
                else
                    u_l <= ul_w;
                if (ur_w > u_r + 16'sd6)
                    u_r <= u_r + 16'sd6;
                else if (ur_w < u_r - 16'sd6)
                    u_r <= u_r - 16'sd6;
                else
                    u_r <= ur_w;
            end
        end
    end

endmodule
