// UART receiver, 8N1 (8 data bits, no parity, 1 stop bit), LSB first.
//
// The serial input is passed through a 2-flop synchronizer, the start bit
// is detected on its falling edge, and every bit is sampled in the middle
// of its bit period.
//
// rx_valid pulses for one clock when a byte has been received (at the
// middle of the stop bit). rx_error is high in the same cycle if the stop
// bit was not 1 (framing error).
`timescale 1ns/1ps

module uart_rx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,        // synchronous, active high
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        rx_error
);

    localparam [2:0] S_IDLE  = 3'd0,
                     S_START = 3'd1,
                     S_DATA  = 3'd2,
                     S_STOP  = 3'd3,
                     S_WAIT  = 3'd4;   // wait for line to return high

    // 2-flop synchronizer (rx is asynchronous to clk)
    reg rx_s1, rx_s;
    always @(posedge clk) begin
        if (rst) begin
            rx_s1 <= 1'b1;
            rx_s  <= 1'b1;
        end else begin
            rx_s1 <= rx;
            rx_s  <= rx_s1;
        end
    end

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;

    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            clk_cnt  <= 16'd0;
            bit_idx  <= 3'd0;
            rx_data  <= 8'd0;
            rx_valid <= 1'b0;
            rx_error <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            rx_error <= 1'b0;

            case (state)
                S_IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (rx_s == 1'b0) state <= S_START;     // falling edge
                end

                // Check the start bit again at its midpoint (glitch filter)
                S_START: begin
                    if (clk_cnt == (CLKS_PER_BIT - 1) / 2) begin
                        clk_cnt <= 16'd0;
                        if (rx_s == 1'b0) state <= S_DATA;
                        else              state <= S_IDLE;  // false start
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end

                // One full bit period after the start-bit midpoint = middle of bit 0, etc.
                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt          <= 16'd0;
                        rx_data[bit_idx] <= rx_s;
                        if (bit_idx == 3'd7) state <= S_STOP;
                        else                 bit_idx <= bit_idx + 3'd1;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end

                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt  <= 16'd0;
                        rx_valid <= 1'b1;
                        rx_error <= ~rx_s;                  // stop bit must be 1
                        state    <= S_WAIT;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end

                S_WAIT: begin
                    if (rx_s == 1'b1) state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
