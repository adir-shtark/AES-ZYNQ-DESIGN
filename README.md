# AES on Cora Z7-07S

AES encryption on a Digilent Cora Z7-07S. A custom Verilog core sits on AXI-Stream, the Zynq processing system feeds it through an AXI DMA, and a bare-metal application sends data from the UART.

Tested with Vivado 2023.1. The application was built with Vitis 2023.2. The board part is `digilentinc.com:cora-z7-07s:part0:1.1` (`xc7z007sclg400-1`).

## Layout

| Path | Contents |
|---|---|
| `rtl/` | AES core used by the block design (`aes_top_level.v` and the round modules) |
| `rtl/tb/` | Testbench for that core |
| `rtl/scratch/` | Earlier top-level from the from-scratch project |
| `rtl/secworks/` | SecWorks AES sources and testbenches, kept as reference |
| `IP/aes_top_level/` | Packaged IP. `component.xml` points at `rtl/` |
| `IP/xci/` | Configured IP instances from the block design |
| `constraints/` | User constraints. This design has none yet |
| `SW/aes_vitis/hello_aes_design/src/` | Application C sources |
| `rebuild_project.tcl` | Recreates the Vivado project |
| `design_1_bd.tcl` | Recreates the block design |

`work/` is where Vivado writes the project. It is not stored in git.

## Rebuild the Vivado project

From this directory, with Vivado 2023.1 on `PATH`:

```bat
vivado -mode batch -source rebuild_project.tcl
```

The script creates `work/aes_design`, rebuilds the block design (processing system, AXI DMA, AES IP, interconnect, and reset), generates the wrapper, and writes `work/aes_design/hw_aes_design.xsa`.

If `work/aes_design` already exists, the script stops. Pass `-tclargs --force` to replace it. Pass `-tclargs --bitstream` to run implementation and include the bitstream in the XSA. Any `.xdc` file placed in `constraints/` is added to the project.

## Software

Open `SW/aes_vitis` in Vitis and use the platform exported from `hw_aes_design.xsa`. The application sources are `helloworld.c`, `platform.c`, `zynq_uart_handler.c`, and their headers. The program reads a block from the UART, pushes it through the DMA to the AES core, and prints the result.
