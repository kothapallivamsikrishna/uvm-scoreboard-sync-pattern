# UVM Scoreboard Synchronization with TLM Analysis FIFO

This repository contains a UVM project that illustrates a robust pattern for building scoreboards: using **`uvm_tlm_analysis_fifo`** to synchronize data from multiple sources before comparison. While the DUT is a simple 4:1 multiplexer, the focus of this project is on the advanced testbench architecture.

---

### Project Overview

A common verification challenge is ensuring that data from the DUT arrives at the scoreboard at the same time as the expected data from a reference model. Simple analysis ports don't guarantee this. The `uvm_tlm_analysis_fifo` solves this by providing a buffered, blocking FIFO on the analysis path.

This project demonstrates this pattern with a testbench containing two monitors:
1.  A standard **DUT Monitor** that captures the actual inputs and outputs of the MUX.
2.  A **Reference Model** that also receives the inputs, independently calculates the expected output, and broadcasts the complete expected transaction.

The scoreboard instantiates two `uvm_tlm_analysis_fifo`s. The `run_phase` of the scoreboard contains a `forever` loop that calls `get()` on both FIFOs. This `get()` task blocks, which naturally **synchronizes the two data streams**. The scoreboard only proceeds to compare the transactions once it has received one from both the DUT monitor and the reference model.



---

### File Structure

-   `rtl/mux_design.v`: Contains the simple Verilog RTL for the 4:1 MUX DUT.
-   `tb/scoreboard_sync_test.sv`: Contains the complete UVM testbench, highlighting the scoreboard implementation.

---

### Key Concepts Illustrated

-   **`uvm_tlm_analysis_fifo`**: A built-in UVM component that combines an analysis export with a FIFO buffer. It's designed specifically for cases where a scoreboard needs to collect transactions from one or more monitors.
-   **Scoreboard Synchronization**: The core pattern being demonstrated. By using a blocking `get()` call on two separate analysis FIFOs, the scoreboard automatically waits until it has a transaction from each source before attempting a comparison, eliminating race conditions.
-   **Reference Model Pattern**: The use of a separate component (`ref_model`) that acts as a "golden" or "predictor" model. This is a standard practice that decouples the checking logic from the scoreboard's comparison mechanism.
-   **Broadcast vs. Point-to-Point**: Shows how analysis ports can broadcast data to multiple subscribers (e.g., from the driver to both the DUT and the reference model), while TLM FIFOs provide a point-to-point connection into the scoreboard.

---

### How to Run

1.  Compile `rtl/mux_design.v` and `tb/scoreboard_sync_test.sv` using a simulator that supports SystemVerilog and UVM.
2.  Set `tb` as the top-level module for simulation.
3.  Execute the simulation. The log will show the DUT monitor and reference model sending transactions, and the scoreboard reporting PASS/FAIL status only after receiving a pair of transactions.
