# UART Transmitter and Receiver in Verilog HDL

A UART (Universal Asynchronous Receiver/Transmitter) written in Verilog HDL: a transmitter, a receiver, and a self-checking testbench. Frame format is **8N1** (1 start bit, 8 data bits LSB first, no parity, 1 stop bit).

## Features
- FSM-based transmitter (`uart_tx`) and receiver (`uart_rx`)
- Baud rate set by one parameter: `CLKS_PER_BIT = clock frequency / baud rate`
  (for example 100 MHz / 115200 = 868, the default)
- Receiver:
  - 2-flop synchronizer on the asynchronous `rx` input
  - Start-bit detection on the falling edge, re-checked at mid-bit to reject glitches
  - Each bit sampled in the middle of its bit period
  - Framing-error flag when the stop bit is not 1
- Transmitter handshake: `tx_start`, `tx_busy`, `tx_done`

## Frame format
```
idle  start  D0  D1  D2  D3  D4  D5  D6  D7  stop  idle
 1      0    <-------- LSB first -------->     1     1
```

## Ports

### `uart_tx`
| Port        | Dir    | Width | Description                                      |
|-------------|--------|-------|--------------------------------------------------|
| `clk`       | input  | 1     | Clock                                            |
| `rst`       | input  | 1     | Synchronous reset, active high                   |
| `tx_start`  | input  | 1     | Pulse for one clock to start sending `tx_data`   |
| `tx_data`   | input  | 8     | Byte to send                                     |
| `tx`        | output | 1     | Serial output (idle high)                        |
| `tx_busy`   | output | 1     | High while a frame is being sent                 |
| `tx_done`   | output | 1     | One-clock pulse at the end of the stop bit       |

### `uart_rx`
| Port       | Dir    | Width | Description                                         |
|------------|--------|-------|-----------------------------------------------------|
| `clk`      | input  | 1     | Clock                                               |
| `rst`      | input  | 1     | Synchronous reset, active high                      |
| `rx`       | input  | 1     | Serial input                                        |
| `rx_data`  | output | 8     | Received byte                                       |
| `rx_valid` | output | 1     | One-clock pulse when a byte has been received       |
| `rx_error` | output | 1     | High with `rx_valid` if the stop bit was 0 (framing error) |

## State machines
- **Transmitter:** `IDLE -> START -> DATA (8 bits) -> STOP -> IDLE`
- **Receiver:** `IDLE -> START (mid-bit check) -> DATA (8 bits) -> STOP -> WAIT -> IDLE`

## Project structure
```
verilog-uart/
├── rtl/   uart_tx.v, uart_rx.v   # design
├── tb/    uart_tb.v              # self-checking testbench
├── sim/   run.sh                 # simulation script (Icarus Verilog)
└── docs/                         # waveform and simulation screenshots
```

## Verification
The testbench uses `CLKS_PER_BIT = 16` to keep simulation short and runs three tests:
1. **Loopback** (`uart_tx` -> `uart_rx`): 8 corner-case bytes (00, FF, 55, AA, A5, 5A, 01, 80) plus a back-to-back burst of 40 random bytes. Every received byte is compared with the byte sent.
2. **Transmitter alone:** the serial line is decoded and checked for start bit = 0, data bits in LSB-first order, and stop bit = 1.
3. **Receiver alone:** frames are driven bit by bit, including frames with a bad stop bit, to check that the framing error is flagged and that the receiver recovers for the next frame.

Result: 74 checks, 0 errors.

## How to run

**Icarus Verilog**
```bash
bash sim/run.sh
# or
iverilog -o sim/uart_sim rtl/uart_tx.v rtl/uart_rx.v tb/uart_tb.v
vvp sim/uart_sim
```
The run writes `uart.vcd`, which can be opened in GTKWave.

**Xilinx Vivado**
1. Create an RTL project.
2. Add `rtl/uart_tx.v` and `rtl/uart_rx.v` as design sources.
3. Add `tb/uart_tb.v` as a simulation source and set `uart_tb` as the simulation top.
4. Run Behavioral Simulation.

Expected end of the console output:
```
Checks: 74, Errors: 0
ALL TESTS PASSED
```

## Notes
- The testbench uses a small `CLKS_PER_BIT` for speed. Set the parameter to your real clock / baud ratio (default 868) for hardware use.
- Parity and multiple stop bits are not implemented.

## Tools
Verilog HDL, Icarus Verilog, Xilinx Vivado (simulation)

## Author
Muhammad Sahil, M.Tech (Signal Processing and Machine Learning), NIT Jalandhar
