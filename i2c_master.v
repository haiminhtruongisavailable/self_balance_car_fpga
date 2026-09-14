// Minimal I2C master: START, 7-bit addr, write/read bytes, STOP, ACK check.
// Open-drain SDA/SCL. 100 kHz at CLK_HZ = 50e6 (override DIV).
module i2c_master #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer I2C_HZ = 100_000
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire       we,          // 1 = write burst, 0 = write reg then read burst
    input  wire [6:0] addr,
    input  wire [7:0] wr_reg,
    input  wire [7:0] wr_data,     // used when we=1 (single data byte after reg)
    input  wire [3:0] rd_n,        // bytes to read when we=0 (1..14)
    output reg        busy,
    output reg        done,
    output reg        nack,
    output reg  [7:0] rd_data0,
    output reg  [7:0] rd_data1,
    output reg  [7:0] rd_data2,
    output reg  [7:0] rd_data3,
    output reg  [7:0] rd_data4,
    output reg  [7:0] rd_data5,
    output reg  [7:0] rd_data6,
    output reg  [7:0] rd_data7,
    output reg  [7:0] rd_data8,
    output reg  [7:0] rd_data9,
    output reg  [7:0] rd_data10,
    output reg  [7:0] rd_data11,
    output reg  [7:0] rd_data12,
    output reg  [7:0] rd_data13,
    inout  wire       scl,
    inout  wire       sda
);

    localparam integer DIV = CLK_HZ / (I2C_HZ * 4);
    localparam [4:0]
        S_IDLE   = 5'd0,
        S_START  = 5'd1,
        S_WA     = 5'd2,
        S_WREG   = 5'd3,
        S_WDATA  = 5'd4,
        S_RSTART = 5'd5,
        S_RA     = 5'd6,
        S_RBYTE  = 5'd7,
        S_STOP   = 5'd8,
        S_DONE   = 5'd9;

    reg [4:0]  state;
    reg [15:0] div_cnt;
    reg [1:0]  q;          // 0..3 quarter-bits
    reg        tick;
    reg        scl_oe;     // 1 = pull low
    reg        sda_oe;
    reg        sda_out;    // value when driving (0)
    reg [7:0]  shreg;
    reg [3:0]  bit_i;
    reg [3:0]  byte_i;
    reg [3:0]  rd_left;
    reg        ack_bit;

    assign scl = scl_oe ? 1'b0 : 1'bz;
    assign sda = sda_oe ? sda_out : 1'bz;

    wire sda_in = sda;

    always @(posedge clk) begin
        if (rst) begin
            div_cnt <= 0;
            tick    <= 1'b0;
        end else if (div_cnt >= DIV[15:0] - 1) begin
            div_cnt <= 0;
            tick    <= 1'b1;
        end else begin
            div_cnt <= div_cnt + 1'b1;
            tick    <= 1'b0;
        end
    end

    task automatic push_rd;
        input [3:0] idx;
        input [7:0] val;
        begin
            case (idx)
                4'd0:  rd_data0  <= val;
                4'd1:  rd_data1  <= val;
                4'd2:  rd_data2  <= val;
                4'd3:  rd_data3  <= val;
                4'd4:  rd_data4  <= val;
                4'd5:  rd_data5  <= val;
                4'd6:  rd_data6  <= val;
                4'd7:  rd_data7  <= val;
                4'd8:  rd_data8  <= val;
                4'd9:  rd_data9  <= val;
                4'd10: rd_data10 <= val;
                4'd11: rd_data11 <= val;
                4'd12: rd_data12 <= val;
                default: rd_data13 <= val;
            endcase
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            busy    <= 1'b0;
            done    <= 1'b0;
            nack    <= 1'b0;
            scl_oe  <= 1'b0;
            sda_oe  <= 1'b0;
            sda_out <= 1'b0;
            q       <= 2'd0;
            bit_i   <= 4'd0;
            byte_i  <= 4'd0;
        end else begin
            done <= 1'b0;
            if (state == S_IDLE) begin
                if (start) begin
                    busy    <= 1'b1;
                    nack    <= 1'b0;
                    rd_left <= (rd_n == 0) ? 4'd1 : rd_n;
                    byte_i  <= 4'd0;
                    state   <= S_START;
                    q       <= 2'd0;
                    // START: SDA high->low while SCL high
                    scl_oe  <= 1'b0;
                    sda_oe  <= 1'b0;
                end
            end else if (tick) begin
                q <= q + 2'd1;
                case (state)
                    S_START: begin
                        case (q)
                            2'd0: begin sda_oe <= 1'b0; scl_oe <= 1'b0; end
                            2'd1: begin sda_oe <= 1'b1; sda_out <= 1'b0; end
                            2'd2: begin scl_oe <= 1'b1; end
                            2'd3: begin
                                shreg <= {addr, 1'b0};
                                bit_i <= 4'd7;
                                state <= S_WA;
                            end
                        endcase
                    end
                    S_WA, S_WREG, S_WDATA, S_RA: begin
                        // send 8 bits + sample ACK
                        if (bit_i != 4'd15) begin
                            case (q)
                                2'd0: begin
                                    scl_oe  <= 1'b1;
                                    sda_oe  <= 1'b1;
                                    sda_out <= shreg[7];
                                end
                                2'd1: scl_oe <= 1'b0;
                                2'd2: ;
                                2'd3: begin
                                    scl_oe <= 1'b1;
                                    shreg  <= {shreg[6:0], 1'b0};
                                    if (bit_i == 0)
                                        bit_i <= 4'd15; // ACK slot next
                                    else
                                        bit_i <= bit_i - 1'b1;
                                end
                            endcase
                        end else begin
                            case (q)
                                2'd0: begin scl_oe <= 1'b1; sda_oe <= 1'b0; end
                                2'd1: scl_oe <= 1'b0;
                                2'd2: ack_bit <= sda_in;
                                2'd3: begin
                                    scl_oe <= 1'b1;
                                    if (ack_bit)
                                        nack <= 1'b1;
                                    bit_i <= 4'd7;
                                    if (state == S_WA) begin
                                        shreg <= wr_reg;
                                        state <= S_WREG;
                                    end else if (state == S_WREG) begin
                                        if (we) begin
                                            shreg <= wr_data;
                                            state <= S_WDATA;
                                        end else begin
                                            state <= S_RSTART;
                                            q     <= 2'd0;
                                        end
                                    end else if (state == S_WDATA) begin
                                        state <= S_STOP;
                                        q     <= 2'd0;
                                    end else begin
                                        // S_RA done: start first read byte
                                        shreg  <= 8'd0;
                                        bit_i  <= 4'd7;
                                        state  <= S_RBYTE;
                                    end
                                end
                            endcase
                        end
                    end
                    S_RSTART: begin
                        case (q)
                            2'd0: begin scl_oe <= 1'b1; sda_oe <= 1'b1; sda_out <= 1'b1; end
                            2'd1: begin scl_oe <= 1'b0; sda_oe <= 1'b0; end
                            2'd2: begin sda_oe <= 1'b1; sda_out <= 1'b0; end
                            2'd3: begin
                                scl_oe <= 1'b1;
                                shreg  <= {addr, 1'b1};
                                bit_i  <= 4'd7;
                                state  <= S_RA;
                            end
                        endcase
                    end
                    S_RBYTE: begin
                        if (bit_i != 4'd15) begin
                            case (q)
                                2'd0: begin scl_oe <= 1'b1; sda_oe <= 1'b0; end
                                2'd1: scl_oe <= 1'b0;
                                2'd2: shreg <= {shreg[6:0], sda_in};
                                2'd3: begin
                                    scl_oe <= 1'b1;
                                    if (bit_i == 0)
                                        bit_i <= 4'd15;
                                    else
                                        bit_i <= bit_i - 1'b1;
                                end
                            endcase
                        end else begin
                            // ACK (0) if more bytes, NACK (1) if last
                            case (q)
                                2'd0: begin
                                    scl_oe  <= 1'b1;
                                    sda_oe  <= 1'b1;
                                    sda_out <= (rd_left == 4'd1) ? 1'b1 : 1'b0;
                                end
                                2'd1: scl_oe <= 1'b0;
                                2'd2: ;
                                2'd3: begin
                                    scl_oe <= 1'b1;
                                    push_rd(byte_i, shreg);
                                    byte_i <= byte_i + 1'b1;
                                    if (rd_left == 4'd1) begin
                                        state <= S_STOP;
                                        q     <= 2'd0;
                                    end else begin
                                        rd_left <= rd_left - 1'b1;
                                        shreg   <= 8'd0;
                                        bit_i   <= 4'd7;
                                    end
                                end
                            endcase
                        end
                    end
                    S_STOP: begin
                        case (q)
                            2'd0: begin scl_oe <= 1'b1; sda_oe <= 1'b1; sda_out <= 1'b0; end
                            2'd1: scl_oe <= 1'b0;
                            2'd2: sda_oe <= 1'b0;
                            2'd3: state <= S_DONE;
                        endcase
                    end
                    S_DONE: begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end
                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
