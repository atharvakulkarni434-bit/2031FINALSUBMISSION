# 8-Channel ADC Peripheral for SCOMP

An 8-channel, 12-bit ADC peripheral for SCOMP (Georgia Tech's instructional processor, ECE 2031), implemented in VHDL on a DE10-Lite FPGA. The peripheral gives SCOMP programmers zero-wait-state access to any of 8 real-world analog channels through a simple memory-mapped read — no channel select, no polling.

Built as the final project for ECE 2031 by a team of 4: Jaivardhan Jain, Atharva Kulkarni, Bret Harvey, and Jad Kahla.

## What it does

The peripheral continuously cycles through all 8 analog input channels in the background via SPI, sampling each one on an LTC2308 ADC and storing the result in a dedicated 12-bit register. A SCOMP program reads any channel instantly with `IN 0xC0` through `IN 0xC7` — the data is always ready, with no wait state and no need to select a channel first.

### Design highlights

- **Continuous background sampling** across all 8 channels, instead of a single-channel select-then-read design — this removes an entire class of programmer error (forgetting to select before reading) and eliminates all polling from the interface.
- **SPI controller** (`LTC2308_ctrl.vhd`) drives the LTC2308 ADC, generating the 12-bit configuration word and handling the conversion timing.
- **Memory-mapped interface** (`ADC_Peripheral_Revised.vhd`) exposes all 8 channels as simple I/O reads to the SCOMP bus.

### Hardware bring-up

Two hardware-only failures were diagnosed and resolved during validation on FPGA:
- A physically rotated ADC connector
- A result-latching race condition between the SPI controller and the channel-result registers

## Files

| File | Description |
|---|---|
| `ADC_Peripheral_Revised.vhd` | Top-level peripheral — background channel cycling, result registers, SCOMP bus interface |
| `LTC2308_ctrl.vhd` | SPI controller for the LTC2308 ADC |
| `GuessingGame.asm` | Demo application: a two-player number-guessing game using analog inputs (CH0, CH7) as player controls, showcasing the peripheral in a real program |
| `SCOMP.sof` | Compiled FPGA bitstream for the DE10-Lite |

## Platform

- **FPGA:** DE10-Lite
- **ADC:** LTC2308 (12-bit, 8-channel)
- **Toolchain:** Quartus Prime
- **Language:** VHDL
