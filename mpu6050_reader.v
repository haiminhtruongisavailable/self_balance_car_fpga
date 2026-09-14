// Wake MPU-6050, set ranges, poll ACCEL/GYRO (14 bytes from 0x3B).
module mpu6050_reader #(
    parameter integer CLK_HZ   = 50_000_000,
    parameter [6:0]   I2C_ADDR = 7'h68,
    parameter integer POLL_HZ  = 100
) (
    input  wire        clk,
    input  wire        rst,
    output wire        busy,
    output reg         sample_valid,
    output reg         error,
    output reg signed [15:0] ax,
    output reg signed [15:0] ay,
    output reg signed [15:0] az,
    output reg signed [15:0] gx,
    output reg signed [15:0] gy,
    output reg signed [15:0] gz,
    inout  wire        scl,
    inout  wire        sda
);

    localparam [7:0]
        REG_SMPLRT   = 8'h19,
        REG_CONFIG   = 8'h1A,
        REG_GYRO_CFG = 8'h1B,
        REG_ACC_CFG  = 8'h1C,
        REG_PWR      = 8'h6B,
        REG_DATA     = 8'h3B;


    localparam integer POLL_DIV = CLK_HZ / POLL_HZ;

    localparam [3:0]
        ST_WAIT  = 4'd0,
        ST_PWR   = 4'd1,
        ST_SR    = 4'd2,
        ST_CFG   = 4'd3,
        ST_GYRO  = 4'd4,
        ST_ACC   = 4'd5,
        ST_IDLE  = 4'd6,
        ST_READ  = 4'd7;

    reg        i2c_start;
    reg        i2c_we;
    reg [7:0]  i2c_reg;
    reg [7:0]  i2c_wdata;
    wire       i2c_busy;
    wire       i2c_done;
    wire       i2c_nack;
    wire [7:0] d0, d1, d2, d3, d4, d5, d6, d7, d8, d9, d10, d11, d12, d13;

    i2c_master #(.CLK_HZ(CLK_HZ), .I2C_HZ(50_000)) u_i2c (
        .clk(clk),
        .rst(rst),
        .start(i2c_start),
        .we(i2c_we),
        .addr(I2C_ADDR),
        .wr_reg(i2c_reg),
        .wr_data(i2c_wdata),
        .rd_n(4'd14),
        .busy(i2c_busy),
        .done(i2c_done),
        .nack(i2c_nack),
        .rd_data0(d0),
        .rd_data1(d1),
        .rd_data2(d2),
        .rd_data3(d3),
        .rd_data4(d4),
        .rd_data5(d5),
        .rd_data6(d6),
        .rd_data7(d7),
        .rd_data8(d8),
        .rd_data9(d9),
        .rd_data10(d10),
        .rd_data11(d11),
        .rd_data12(d12),
        .rd_data13(d13),
        .scl(scl),
        .sda(sda)
    );

    assign busy = i2c_busy;

    reg [3:0]  st;
    reg [23:0] wait_cnt;
    reg [31:0] poll_cnt;
    reg        kick;

    always @(posedge clk) begin
        if (rst) begin
            st           <= ST_WAIT;
            wait_cnt     <= 24'd0;
            poll_cnt     <= 32'd0;
            i2c_start    <= 1'b0;
            sample_valid <= 1'b0;
            error        <= 1'b0;
            kick         <= 1'b0;
        end else begin
            i2c_start    <= 1'b0;
            sample_valid <= 1'b0;

            case (st)
                ST_WAIT: begin
                    // ~50 ms after reset for MPU POR
                    if (wait_cnt == CLK_HZ / 20) begin
                        st       <= ST_PWR;
                        i2c_we   <= 1'b1;
                        i2c_reg  <= REG_PWR;
                        i2c_wdata<= 8'h00;
                        i2c_start<= 1'b1;
                    end else
                        wait_cnt <= wait_cnt + 1'b1;
                end
                ST_PWR: if (i2c_done) begin
                    error    <= i2c_nack;
                    i2c_reg  <= REG_SMPLRT;
                    i2c_wdata<= 8'h07;
                    i2c_start<= 1'b1;
                    st       <= ST_SR;
                end
                ST_SR: if (i2c_done) begin
                    error    <= error | i2c_nack;
                    i2c_reg  <= REG_CONFIG;
                    i2c_wdata<= 8'h03;
                    i2c_start<= 1'b1;
                    st       <= ST_CFG;
                end
                ST_CFG: if (i2c_done) begin
                    error    <= error | i2c_nack;
                    i2c_reg  <= REG_GYRO_CFG;
                    i2c_wdata<= 8'h00;
                    i2c_start<= 1'b1;
                    st       <= ST_GYRO;
                end
                ST_GYRO: if (i2c_done) begin
                    error    <= error | i2c_nack;
                    i2c_reg  <= REG_ACC_CFG;
                    i2c_wdata<= 8'h00;
                    i2c_start<= 1'b1;
                    st       <= ST_ACC;
                end
                ST_ACC: if (i2c_done) begin
                    error    <= error | i2c_nack;
                    st       <= ST_IDLE;
                    poll_cnt <= 32'd0;
                end
                ST_IDLE: begin
                    if (poll_cnt >= POLL_DIV - 1) begin
                        poll_cnt  <= 32'd0;
                        i2c_we    <= 1'b0;
                        i2c_reg   <= REG_DATA;
                        i2c_wdata <= 8'h00;
                        i2c_start <= 1'b1;
                        st        <= ST_READ;
                    end else
                        poll_cnt <= poll_cnt + 1'b1;
                end
                ST_READ: if (i2c_done) begin
                    if (!i2c_nack) begin
                        error        <= 1'b0;
                        ax           <= {d0, d1};
                        ay           <= {d2, d3};
                        az           <= {d4, d5};
                        gx           <= {d8, d9};
                        gy           <= {d10, d11};
                        gz           <= {d12, d13};
                        sample_valid <= 1'b1;
                    end else begin
                        error        <= 1'b1;
                        sample_valid <= 1'b0;
                    end
                    st <= ST_IDLE;
                end
                default: st <= ST_WAIT;
            endcase
        end
    end

endmodule
