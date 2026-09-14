// 8N1 UART transmitter.
module uart_tx #(
    parameter integer CLK_HZ  = 50_000_000,
    parameter integer BAUD    = 115200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire       wr,
    output reg        busy,
    output reg        tx
);

    localparam integer DIV = CLK_HZ / BAUD;

    reg [15:0] div_cnt;
    reg [3:0]  bit_i;
    reg [9:0]  sh; // {stop, data[7:0], start}

    always @(posedge clk) begin
        if (rst) begin
            busy    <= 1'b0;
            tx      <= 1'b1;
            div_cnt <= 16'd0;
            bit_i   <= 4'd0;
        end else if (!busy) begin
            if (wr) begin
                busy    <= 1'b1;
                sh      <= {1'b1, data, 1'b0};
                bit_i   <= 4'd0;
                div_cnt <= 16'd0;
                tx      <= 1'b0;
            end
        end else if (div_cnt >= DIV[15:0] - 1) begin
            div_cnt <= 16'd0;
            if (bit_i == 4'd9) begin
                busy <= 1'b0;
                tx   <= 1'b1;
            end else begin
                bit_i <= bit_i + 1'b1;
                sh    <= {1'b1, sh[9:1]};
                tx    <= sh[1];
            end
        end else
            div_cnt <= div_cnt + 1'b1;
    end

endmodule
