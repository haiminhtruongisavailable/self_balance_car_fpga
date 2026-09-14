// Hex log (CRLF): ax ay az theta uL uR flags
// flags bit0=armed bit1=killed. theta = 0.01 deg. u = duty percent.
module ascii_sample (
    input  wire        clk,
    input  wire        rst,
    input  wire        kick,
    input  wire signed [15:0] ax,
    input  wire signed [15:0] ay,
    input  wire signed [15:0] az,
    input  wire signed [15:0] theta,
    input  wire signed [15:0] u_l,
    input  wire signed [15:0] u_r,
    input  wire        armed,
    input  wire        killed,
    output reg         uart_wr,
    output reg  [7:0]  uart_data,
    input  wire        uart_busy,
    output reg         done
);

    reg [5:0]  idx;
    reg        run;
    reg [7:0]  line [0:47];
    integer    i;

    function [7:0] hex4;
        input [3:0] n;
        begin
            hex4 = (n < 10) ? (8'h30 + n) : (8'h41 + (n - 4'd10));
        end
    endfunction

    task automatic put16;
        input integer base;
        input [15:0] v;
        begin
            line[base+0] <= hex4(v[15:12]);
            line[base+1] <= hex4(v[11:8]);
            line[base+2] <= hex4(v[7:4]);
            line[base+3] <= hex4(v[3:0]);
        end
    endtask

    always @(posedge clk) begin
        uart_wr <= 1'b0;
        done    <= 1'b0;
        if (rst) begin
            run <= 1'b0;
            idx <= 6'd0;
            for (i = 0; i < 48; i = i + 1)
                line[i] <= 8'h20;
        end else if (!run && kick) begin
            put16(0,  ax);
            line[4]  <= 8'h20;
            put16(5,  ay);
            line[9]  <= 8'h20;
            put16(10, az);
            line[14] <= 8'h20;
            put16(15, theta);
            line[19] <= 8'h20;
            put16(20, u_l);
            line[24] <= 8'h20;
            put16(25, u_r);
            line[29] <= 8'h20;
            put16(30, {14'd0, killed, armed});
            line[34] <= 8'h0D;
            line[35] <= 8'h0A;
            idx <= 6'd0;
            run <= 1'b1;
        end else if (run && !uart_busy && !uart_wr) begin
            if (idx >= 6'd36) begin
                run  <= 1'b0;
                done <= 1'b1;
            end else begin
                uart_data <= line[idx];
                uart_wr   <= 1'b1;
                idx       <= idx + 1'b1;
            end
        end
    end

endmodule
