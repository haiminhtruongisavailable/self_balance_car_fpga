// 8N1 UART receiver. Sample 16x baud.
module uart_rx #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);
    localparam integer DIV = CLK_HZ / (BAUD * 16);

    reg [15:0] div_cnt;
    reg        tick;
    reg [3:0]  tick16;
    reg [2:0]  bit_i;
    reg [7:0]  sh;
    reg [1:0]  st;
    reg        rx_s0, rx_s1;

    localparam [1:0] IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    always @(posedge clk) begin
        if (rst) begin
            div_cnt <= 16'd0;
            tick    <= 1'b0;
        end else if (div_cnt >= DIV[15:0] - 1) begin
            div_cnt <= 16'd0;
            tick    <= 1'b1;
        end else begin
            div_cnt <= div_cnt + 1'b1;
            tick    <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            rx_s0 <= 1'b1;
            rx_s1 <= 1'b1;
        end else begin
            rx_s0 <= rx;
            rx_s1 <= rx_s0;
        end
    end

    always @(posedge clk) begin
        valid <= 1'b0;
        if (rst) begin
            st     <= IDLE;
            tick16 <= 4'd0;
            bit_i  <= 3'd0;
            data   <= 8'd0;
        end else if (tick) begin
            case (st)
                IDLE: if (rx_s1 == 1'b0) begin
                    st     <= START;
                    tick16 <= 4'd0;
                end
                START: begin
                    if (tick16 == 4'd7) begin
                        if (rx_s1 == 1'b0) begin
                            st     <= DATA;
                            tick16 <= 4'd0;
                            bit_i  <= 3'd0;
                        end else
                            st <= IDLE;
                    end else
                        tick16 <= tick16 + 1'b1;
                end
                DATA: begin
                    if (tick16 == 4'd15) begin
                        tick16 <= 4'd0;
                        sh     <= {rx_s1, sh[7:1]};
                        if (bit_i == 3'd7)
                            st <= STOP;
                        else
                            bit_i <= bit_i + 1'b1;
                    end else
                        tick16 <= tick16 + 1'b1;
                end
                STOP: begin
                    if (tick16 == 4'd15) begin
                        data  <= sh;
                        valid <= 1'b1;
                        st    <= IDLE;
                        tick16<= 4'd0;
                    end else
                        tick16 <= tick16 + 1'b1;
                end
                default: st <= IDLE;
            endcase
        end
    end
endmodule
