// Complementary filter: MPU-6050 → theta, theta_dot.
//
// Units (signed 16-bit):
//   theta     = 0.01 deg     ( 3000 = 30.00°)
//   theta_dot = 0.01 deg/s   (10000 = 100.00 deg/s)
//
// Pitch from CORDIC atan2(acc_y, acc_x). Rate from selected gyro.
// AXIS: 0 = atan2(ax,az)+gy   1 = atan2(ay,az)+gx   2 = atan2(az,ax)+gy
// theta = a*(theta + g*dt) + (1-a)*theta_acc,  a = ALPHA/256.
module comp_filter #(
    parameter integer POLL_HZ = 100,
    parameter integer AXIS    = 1,
    parameter [7:0]   ALPHA   = 8'd252,
    parameter signed [15:0] OFFSET = 16'sd0
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        valid_i,
    input  wire signed [15:0] ax,
    input  wire signed [15:0] ay,
    input  wire signed [15:0] az,
    input  wire signed [15:0] gx,
    input  wire signed [15:0] gy,
    input  wire signed [15:0] gz,
    output reg         valid_o,
    output reg  signed [15:0] theta,
    output reg  signed [15:0] theta_dot
);

    localparam signed [31:0] GYRO_DT_MUL  = (100 * 65536) / (131 * POLL_HZ);
    localparam signed [31:0] GYRO_DOT_MUL = (100 * 65536) / 131;

    localparam signed [15:0]
        ATAN0  = 16'sd4500,
        ATAN1  = 16'sd2657,
        ATAN2  = 16'sd1404,
        ATAN3  = 16'sd713,
        ATAN4  = 16'sd358,
        ATAN5  = 16'sd179,
        ATAN6  = 16'sd90,
        ATAN7  = 16'sd45,
        ATAN8  = 16'sd22,
        ATAN9  = 16'sd11,
        ATAN10 = 16'sd6,
        ATAN11 = 16'sd3,
        ATAN12 = 16'sd1,
        ATAN13 = 16'sd1,
        ATAN14 = 16'sd0,
        ATAN15 = 16'sd0;

    function signed [15:0] atan_k;
        input [3:0] k;
        begin
            case (k)
                4'd0:  atan_k = ATAN0;
                4'd1:  atan_k = ATAN1;
                4'd2:  atan_k = ATAN2;
                4'd3:  atan_k = ATAN3;
                4'd4:  atan_k = ATAN4;
                4'd5:  atan_k = ATAN5;
                4'd6:  atan_k = ATAN6;
                4'd7:  atan_k = ATAN7;
                4'd8:  atan_k = ATAN8;
                4'd9:  atan_k = ATAN9;
                4'd10: atan_k = ATAN10;
                4'd11: atan_k = ATAN11;
                4'd12: atan_k = ATAN12;
                4'd13: atan_k = ATAN13;
                4'd14: atan_k = ATAN14;
                default: atan_k = ATAN15;
            endcase
        end
    endfunction

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

    localparam [1:0]
        ST_IDLE = 2'd0,
        ST_PRE  = 2'd1,
        ST_ITER = 2'd2,
        ST_FUSE = 2'd3;

    reg [1:0]  st;
    reg [3:0]  iter;
    reg signed [31:0] cx, cy;
    reg signed [15:0] cang;
    reg signed [15:0] gy_hold;
    reg               primed;
    reg signed [15:0] theta_i;

    wire signed [15:0] acc_x =
        (AXIS == 0) ? az :
        (AXIS == 1) ? az : ax;
    wire signed [15:0] acc_y =
        (AXIS == 0) ? ax :
        (AXIS == 1) ? ay : az;
    wire signed [15:0] gyr =
        (AXIS == 1) ? gx : gy;

    wire signed [31:0] gy_sx    = {{16{gy_hold[15]}}, gy_hold};
    wire signed [31:0] dtheta_w = (gy_sx * GYRO_DT_MUL) >>> 16;
    wire signed [31:0] tdot_w   = (gy_sx * GYRO_DOT_MUL) >>> 16;

    wire signed [31:0] theta_g  = $signed({{16{theta_i[15]}}, theta_i}) + dtheta_w;
    wire signed [31:0] fused    =
        ( $signed({24'd0, ALPHA}) * theta_g
        + $signed({23'd0, (9'd256 - {1'b0, ALPHA})}) * $signed({{16{cang[15]}}, cang})
        ) >>> 8;

    always @(posedge clk) begin
        valid_o <= 1'b0;
        if (rst) begin
            st        <= ST_IDLE;
            iter      <= 4'd0;
            theta     <= 16'sd0;
            theta_i   <= 16'sd0;
            theta_dot <= 16'sd0;
            gy_hold   <= 16'sd0;
            primed    <= 1'b0;
            cx        <= 32'sd0;
            cy        <= 32'sd0;
            cang      <= 16'sd0;
        end else begin
            case (st)
                ST_IDLE: if (valid_i) begin
                    gy_hold <= gyr;
                    iter    <= 4'd0;
                    // (0,0) is not 90° — CORDIC would sum the whole atan table (~99.90°)
                    if ((acc_x == 16'sd0) && (acc_y == 16'sd0)) begin
                        cang    <= 16'sd0;
                        cx      <= 32'sd0;
                        cy      <= 32'sd0;
                        st      <= ST_FUSE;
                    end else begin
                        cx      <= {{8{acc_x[15]}}, acc_x, 8'd0};
                        cy      <= {{8{acc_y[15]}}, acc_y, 8'd0};
                        cang    <= 16'sd0;
                        st      <= ST_PRE;
                    end
                end
                ST_PRE: begin
                    if (cx[31]) begin
                        cx   <= -cx;
                        cy   <= -cy;
                        cang <= cy[31] ? -16'sd18000 : 16'sd18000;
                    end
                    st <= ST_ITER;
                end
                ST_ITER: begin
                    if (!cy[31]) begin
                        cx   <= cx + (cy >>> iter);
                        cy   <= cy - (cx >>> iter);
                        cang <= cang + atan_k(iter);
                    end else begin
                        cx   <= cx - (cy >>> iter);
                        cy   <= cy + (cx >>> iter);
                        cang <= cang - atan_k(iter);
                    end
                    if (iter == 4'd15)
                        st <= ST_FUSE;
                    else
                        iter <= iter + 1'b1;
                end
                ST_FUSE: begin
                    if (!primed)
                        theta_i <= cang;
                    else
                        theta_i <= sat16(fused);
                    // OFFSET only on the output, not inside the loop
                    if (!primed)
                        theta <= sat16($signed({{16{cang[15]}}, cang}) - {{16{OFFSET[15]}}, OFFSET});
                    else
                        theta <= sat16(fused - {{16{OFFSET[15]}}, OFFSET});
                    primed    <= 1'b1;
                    theta_dot <= sat16(tdot_w);
                    valid_o   <= 1'b1;
                    st        <= ST_IDLE;
                end
                default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
