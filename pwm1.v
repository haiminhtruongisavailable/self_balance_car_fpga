// One PWM channel. duty_pct = 0..100. Period = CLK_HZ/PWM_HZ ticks.
module pwm1 #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 1000
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [6:0] duty_pct,  // 0..100
    output reg        pwm
);
    localparam integer PERIOD = CLK_HZ / PWM_HZ;

    reg [31:0] cnt;
    wire [31:0] thresh = (PERIOD * duty_pct) / 100;

    always @(posedge clk) begin
        if (rst) begin
            cnt <= 32'd0;
            pwm <= 1'b0;
        end else begin
            if (cnt >= PERIOD - 1)
                cnt <= 32'd0;
            else
                cnt <= cnt + 1'b1;
            pwm <= (cnt < thresh) && (duty_pct != 7'd0);
        end
    end
endmodule
