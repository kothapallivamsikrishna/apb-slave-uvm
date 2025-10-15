# APB Slave RAM Verification using UVM

This repository contains the Verilog RTL for an APB (Advanced Peripheral Bus) slave RAM and a comprehensive UVM testbench designed to verify its protocol compliance and functionality. This project demonstrates the verification of a standard ARM-based bus protocol, a critical skill in modern SoC verification.

---



### Project Overview

The primary goal is to verify that the APB slave RAM correctly handles read and write transactions from a bus master. The UVM environment is built to emulate an APB master, driving the bus signals and checking the slave's responses.

-   **DUT**: An `apb_ram` module that acts as a simple 32-word memory slave on an APB bus. It responds to 32-bit read and write commands.
-   **Verification Environment**: A UVM testbench that acts as an **APB Master**.
    -   The **Driver** emulates the master's behavior, driving the APB protocol's two-phase `SETUP` and `ACCESS` states by managing the `PSEL`, `PENABLE`, and other bus signals.
    -   The **Monitor** captures transactions from the bus by observing the protocol signals.
    -   A **Scoreboard** with an internal memory model is used to verify data integrity for both valid and invalid transactions.

---

### Folder Structure

-   `rtl/apb_design.v`: Contains the Verilog RTL for the APB Slave RAM.
-   `tb/apb_tb.sv`: Contains the complete SystemVerilog/UVM testbench that emulates an APB Master.

---

### Key Verification Components

-   **Protocol-Aware Driver**: The driver is responsible for correctly generating the APB `SETUP` and `ACCESS` phases. It asserts `PSEL` to initiate a transfer and then asserts `PENABLE` on the next cycle, waiting for `PREADY` from the slave to complete the transaction.
-   **Error Injection Sequences**: The testbench includes dedicated sequences (`write_err`, `read_err`) that generate transactions to invalid addresses. This allows verification of the slave's `PSLVERR` (slave error) response mechanism.
-   **Predictive Scoreboard**: The scoreboard maintains a local memory model. It checks read data against its model and also verifies that `PSLVERR` is correctly asserted for out-of-bounds accesses and de-asserted for valid ones.
-   **Test Layer Control**: The environment uses separate UVM tests (`sanity_test`, `error_test`) to cleanly separate the verification of normal operation from error condition testing.

---

### How to Run

1.  Compile both `rtl/apb_design.v` and `tb/apb_tb.sv` using a simulator that supports SystemVerilog and UVM.
2.  In `tb/apb_tb.sv`, you can switch between tests by changing the `run_test()` argument (e.g., from `run_test("sanity_test");` to `run_test("error_test");`).
3.  Set `tb` as the top-level module and execute the simulation. The scoreboard will report the PASS/FAIL status of each transaction.
