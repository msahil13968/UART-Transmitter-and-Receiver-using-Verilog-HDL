// Self-checking testbench for uart_tx and uart_rx
//
//  Test 1: loopback (tx -> rx), single bytes and back-to-back burst
//  Test 2: transmitter checked alone by decoding its serial line
//  Test 3: receiver checked alone with a bit-banged serial frame,
//          including framing-error (stop bit = 0) frames
`timescale 1ns/1ps

module uart_tb;

    localparam CPB = 16;                  // small value to keep simulation short

    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;                 // 100 MHz

    integer errors = 0;
    integer checks = 0;

    // -------------------- Test 1: loopback --------------------
    reg        tx_start = 0;
    reg  [7:0] tx_data  = 0;
    wire       serial;
    wire       tx_busy, tx_done;
    wire [7:0] rx_data;
    wire       rx_valid, rx_error;

    uart_tx #(.CLKS_PER_BIT(CPB)) u_tx (
        .clk(clk), .rst(rst), .tx_start(tx_start), .tx_data(tx_data),
        .tx(serial), .tx_busy(tx_busy), .tx_done(tx_done));

    uart_rx #(.CLKS_PER_BIT(CPB)) u_rx (
        .clk(clk), .rst(rst), .rx(serial),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_error(rx_error));

    reg [7:0] lb_mem  [0:255];            // bytes received in loopback
    reg [7:0] exp_mem [0:255];            // bytes sent in loopback
    integer   lb_n = 0, sent = 0;
    integer   lb_err = 0;

    always @(posedge clk) begin
        if (rx_valid) begin
            lb_mem[lb_n] = rx_data;
            if (rx_error) lb_err = lb_err + 1;
            lb_n = lb_n + 1;
        end
    end

    task send_byte;
        input [7:0] d;
        begin
            @(negedge clk);
            while (tx_busy) @(negedge clk);
            tx_data  = d;
            tx_start = 1'b1;
            exp_mem[sent] = d;
            sent = sent + 1;
            @(negedge clk);
            tx_start = 1'b0;
            if (tx_busy !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL: tx_busy not asserted after tx_start");
            end
        end
    endtask

    task wait_all_received;
        integer guard;
        begin
            guard = 0;
            while (lb_n < sent && guard < 100000) begin
                @(negedge clk);
                guard = guard + 1;
            end
        end
    endtask

    task compare_loopback;
        integer i;
        begin
            for (i = 0; i < sent; i = i + 1) begin
                checks = checks + 1;
                if (lb_mem[i] !== exp_mem[i]) begin
                    errors = errors + 1;
                    $display("FAIL loopback #%0d: sent %h, received %h", i, exp_mem[i], lb_mem[i]);
                end else
                    $display("PASS loopback #%0d: %h", i, lb_mem[i]);
            end
            if (lb_n !== sent) begin
                errors = errors + 1;
                $display("FAIL: sent %0d bytes but received %0d", sent, lb_n);
            end
            if (lb_err != 0) begin
                errors = errors + 1;
                $display("FAIL: %0d unexpected framing errors in loopback", lb_err);
            end
        end
    endtask

    // -------------------- Test 2: transmitter alone --------------------
    reg        tx2_start = 0;
    reg  [7:0] tx2_data  = 0;
    wire       tx2_line, tx2_busy, tx2_done;

    uart_tx #(.CLKS_PER_BIT(CPB)) u_tx2 (
        .clk(clk), .rst(rst), .tx_start(tx2_start), .tx_data(tx2_data),
        .tx(tx2_line), .tx_busy(tx2_busy), .tx_done(tx2_done));

    task wait_clks;
        input integer n;
        begin
            repeat (n) @(posedge clk);
            #1;
        end
    endtask

    task check_tx_frame;
        input [7:0] d;
        reg   [7:0] got;
        integer     i;
        begin
            tx2_data = d;
            @(negedge clk);
            tx2_start = 1'b1;
            @(posedge clk);               // tx accepts the byte on this edge
            #1;
            tx2_start = 1'b0;

            wait_clks(CPB / 2);           // middle of start bit
            checks = checks + 1;
            if (tx2_line !== 1'b0) begin
                errors = errors + 1;
                $display("FAIL tx %h: start bit is not 0", d);
            end

            for (i = 0; i < 8; i = i + 1) begin
                wait_clks(CPB);           // middle of data bit i
                got[i] = tx2_line;
            end

            wait_clks(CPB);               // middle of stop bit
            checks = checks + 1;
            if (tx2_line !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL tx %h: stop bit is not 1", d);
            end

            checks = checks + 1;
            if (got !== d) begin
                errors = errors + 1;
                $display("FAIL tx: sent %h, line carried %h (LSB first)", d, got);
            end else
                $display("PASS tx frame: %h (start=0, 8 data bits LSB first, stop=1)", d);

            wait_clks(CPB);               // let it return to idle
        end
    endtask

    // -------------------- Test 3: receiver alone --------------------
    reg        rx2_line = 1'b1;
    wire [7:0] rx2_data;
    wire       rx2_valid, rx2_error;

    uart_rx #(.CLKS_PER_BIT(CPB)) u_rx2 (
        .clk(clk), .rst(rst), .rx(rx2_line),
        .rx_data(rx2_data), .rx_valid(rx2_valid), .rx_error(rx2_error));

    reg [7:0] rx2_last;
    reg       rx2_last_err;
    integer   rx2_n = 0;

    always @(posedge clk) begin
        if (rx2_valid) begin
            rx2_last     = rx2_data;
            rx2_last_err = rx2_error;
            rx2_n        = rx2_n + 1;
        end
    end

    // Drive one serial frame on rx2_line
    task send_serial;
        input [7:0] d;
        input       stop_bit;
        integer     i;
        begin
            @(negedge clk);
            rx2_line = 1'b0;                          // start bit
            repeat (CPB) @(negedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx2_line = d[i];
                repeat (CPB) @(negedge clk);
            end
            rx2_line = stop_bit;                      // stop bit
            repeat (CPB) @(negedge clk);
            rx2_line = 1'b1;
        end
    endtask

    task check_rx_frame;
        input [7:0] d;
        input       stop_bit;
        integer     n_before;
        begin
            n_before = rx2_n;
            send_serial(d, stop_bit);
            repeat (CPB) @(negedge clk);
            checks = checks + 1;
            if (rx2_n !== n_before + 1) begin
                errors = errors + 1;
                $display("FAIL rx %h: rx_valid pulses = %0d (expected 1)", d, rx2_n - n_before);
            end else if (rx2_last !== d) begin
                errors = errors + 1;
                $display("FAIL rx: line carried %h, received %h", d, rx2_last);
            end else if (rx2_last_err !== ~stop_bit) begin
                errors = errors + 1;
                $display("FAIL rx %h: rx_error = %b, expected %b", d, rx2_last_err, ~stop_bit);
            end else
                $display("PASS rx frame: %h%s", d, stop_bit ? "" : " (framing error flagged)");
        end
    endtask

    // -------------------- Main sequence --------------------
    integer t, seed;

    initial begin
        $dumpfile("uart.vcd");
        $dumpvars(0, uart_tb);

        repeat (5) @(negedge clk);
        rst = 1'b0;
        repeat (5) @(negedge clk);

        // Test 1a: single bytes, corner patterns
        $display("--- Test 1: loopback ---");
        send_byte(8'h00); send_byte(8'hFF); send_byte(8'h55); send_byte(8'hAA);
        send_byte(8'hA5); send_byte(8'h5A); send_byte(8'h01); send_byte(8'h80);
        wait_all_received;
        // Test 1b: back-to-back burst with random data
        seed = 32'hBEEF;
        for (t = 0; t < 40; t = t + 1) send_byte($random(seed));
        wait_all_received;
        compare_loopback;

        // Test 2: transmitter alone
        $display("--- Test 2: transmitter ---");
        check_tx_frame(8'h00);
        check_tx_frame(8'hFF);
        check_tx_frame(8'h55);
        check_tx_frame(8'hA3);
        check_tx_frame(8'h81);
        check_tx_frame(8'h7E);

        // Test 3: receiver alone
        $display("--- Test 3: receiver ---");
        check_rx_frame(8'h00, 1'b1);
        check_rx_frame(8'hFF, 1'b1);
        check_rx_frame(8'h5A, 1'b1);
        check_rx_frame(8'hC3, 1'b1);
        check_rx_frame(8'h3C, 1'b0);      // framing error (stop bit = 0)
        check_rx_frame(8'h96, 1'b1);      // receiver recovers afterwards
        check_rx_frame(8'hE1, 1'b0);      // framing error again
        check_rx_frame(8'h0F, 1'b1);

        $display("--------------------------------------------");
        $display("Checks: %0d, Errors: %0d", checks, errors);
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("SOME TESTS FAILED");
        $finish;
    end

    // Watchdog
    initial begin
        #20_000_000;
        $display("TIMEOUT: simulation did not finish");
        $finish;
    end

endmodule
