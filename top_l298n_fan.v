// Practice top: one 5 V fan on L298N OUT1/OUT2. Not the balancer.
// Quartus: set THIS as top (not top_module) for the fan test only.
//
// PuTTY 115200:  0=stop  1=20%  2=40%  3=60%  4=80%  f=fwd  r=rev
module top_l298n_fan (
    input  wire        CLOCK_50,
    input  wire [1:0]  KEY,
    output wire [7:0]  LED,
    inout  wire [12:0] GPIO_2,
    input  wire        GPIO_2_IN0      // JP3 UART RX  PIN_E15
);

    localparam integer CLK_HZ = 50_000_000;

    wire rst = ~KEY[0];

    // JP3: [3]=ENA [5]=IN1 [6]=IN2   [2]=UART TX echo
    wire ena, in1, in2, uart_tx;

    assign GPIO_2[3] = ena;
    assign GPIO_2[5] = in1;
    assign GPIO_2[6] = in2;
    assign GPIO_2[2] = uart_tx;
    assign GPIO_2[0] = 1'bz;
    assign GPIO_2[1] = 1'bz;
    assign GPIO_2[4] = 1'b0;
    assign GPIO_2[7] = 1'b0;
    assign GPIO_2[8] = 1'b0;
    assign GPIO_2[9] = 1'bz;
    assign GPIO_2[10]= 1'bz;
    assign GPIO_2[11]= 1'bz;
    assign GPIO_2[12]= 1'bz;

    wire [7:0] rx_byte;
    wire       rx_valid;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(115200)) u_rx (
        .clk(CLOCK_50),
        .rst(rst),
        .rx(GPIO_2_IN0),
        .data(rx_byte),
        .valid(rx_valid)
    );

    wire uart_busy;
    reg        uart_wr;
    reg  [7:0] uart_data;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(115200)) u_tx (
        .clk(CLOCK_50),
        .rst(rst),
        .data(uart_data),
        .wr(uart_wr),
        .busy(uart_busy),
        .tx(uart_tx)
    );

    reg [6:0] duty_pct;  // 0..80
    reg       fwd;       // 1 = IN1=1 IN2=0

    pwm1 #(.CLK_HZ(CLK_HZ), .PWM_HZ(1000)) u_pwm (
        .clk(CLOCK_50),
        .rst(rst),
        .duty_pct(duty_pct),
        .pwm(ena)
    );

    assign in1 = fwd;
    assign in2 = ~fwd & (duty_pct != 7'd0);

    always @(posedge CLOCK_50) begin
        uart_wr <= 1'b0;
        if (rst) begin
            duty_pct <= 7'd0;
            fwd      <= 1'b1;
        end else if (rx_valid) begin
            case (rx_byte)
                8'h30: duty_pct <= 7'd0;    // '0'
                8'h31: duty_pct <= 7'd20;   // '1'
                8'h32: duty_pct <= 7'd40;
                8'h33: duty_pct <= 7'd60;
                8'h34: duty_pct <= 7'd80;   // cap 80%
                8'h66, 8'h46: fwd <= 1'b1; // 'f' 'F'
                8'h72, 8'h52: fwd <= 1'b0; // 'r' 'R'
                8'h73, 8'h53: duty_pct <= 7'd0; // 's'
                default: ;
            endcase
            if (!uart_busy) begin
                uart_data <= rx_byte;
                uart_wr   <= 1'b1;
            end
        end
    end

    assign LED[0] = ena;
    assign LED[1] = in1;
    assign LED[2] = in2;
    assign LED[7:3] = 5'b0;

endmodule
