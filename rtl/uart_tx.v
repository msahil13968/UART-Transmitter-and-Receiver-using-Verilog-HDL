// UART transmitter, 8N1 (8 data bits, no parity, 1 stop bit), LSB first.
//
// CLKS_PER_BIT = clock frequency / baud rate
//   e.g. 100 MHz / 115200 baud = 868
//
// Usage: put the byte on tx_data and pulse tx_start for one clock while
// tx_busy is low. tx_busy stays high until the stop bit has been sent;
// tx_done pulses for one clock when the frame is finished.
`timescale 1ns/1ps

module uart_tx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,        // synchronous, active high
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output wire       tx,         // serial line (idle high)
    output wire       tx_busy,
    output reg        tx_done
);

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;           // counts clocks within one bit period
    reg [2:0]  bit_idx;
    reg [7:0]  shift;

    assign tx_busy = (state != S_IDLE);
    assign tx = (state == S_START) ? 1'b0 :
                (state == S_DATA)  ? shift[bit_idx] :
                                     1'b1;           // IDLE and STOP

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            clk_cnt <= 16'd0;
            bit_idx <= 3'd0;
            shift   <= 8'd0;
            tx_done <= 1'b0;
        end else begin
            tx_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (tx_start) begin
                        shift <= tx_data;
                        state <= S_START;
                    end
                end

                S_START: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        state   <= S_DATA;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end

                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        if (bit_idx == 3'd7) state <= S_STOP;
                        else                 bit_idx <= bit_idx + 3'd1;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end

                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        tx_done <= 1'b1;
                        state   <= S_IDLE;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end
            endcase
        end
    end

endmodule
