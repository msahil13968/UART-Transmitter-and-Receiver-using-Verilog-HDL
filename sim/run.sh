#!/bin/bash
# Run from the project root: bash sim/run.sh
iverilog -o sim/uart_sim rtl/uart_tx.v rtl/uart_rx.v tb/uart_tb.v && vvp sim/uart_sim
