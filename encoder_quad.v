// Quadrature count, one wheel.
// Sample A/B on clk (FPGA CLOCK_50). On A 0->1: B==0 => +1, else -1.
module encoder_quad (
    input  wire              clk,
    input  wire              rst,
    input  wire              a,
    input  wire              b,
    output reg signed [31:0] count
);
    reg a_s0, a_s1, a_prev;
    reg b_s0, b_s1;

    always @(posedge clk) begin
        if (rst) begin
            a_s0   <= 1'b0;
            a_s1   <= 1'b0;
            a_prev <= 1'b0;
            b_s0   <= 1'b0;
            b_s1   <= 1'b0;
            count  <= 32'sd0;
        end else begin
            a_s0   <= a;
            a_s1   <= a_s0;
            b_s0   <= b;
            b_s1   <= b_s0;
            a_prev <= a_s1;
            if (a_s1 & ~a_prev) begin
                if (b_s1 == 1'b0)
                    count <= count + 32'sd1;
                else
                    count <= count - 32'sd1;
            end
        end
    end
endmodule
