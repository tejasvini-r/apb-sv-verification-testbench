# APB Slave — Layered SystemVerilog Testbench (Non-UVM)

A self-contained, class-based SV verification environment for a small
APB (Advanced Peripheral Bus) register-file slave. No UVM, no pure
assertion-only checking — this is the classic "layered testbench"
architecture (generator → driver → monitor → scoreboard → coverage)
built directly on `mailbox`, `virtual interface`, and `clocking block`
constructs, so every line is something you can explain in an interview.

## Files

| File | Role |
|---|---|
| `apb_slave_dut.sv` | DUT: 16x32-bit APB register file with 3 intentional quirks (see below) |
| `apb_if.sv` | Interface with separate driver/monitor clocking blocks |
| `apb_transaction.sv` | Randomized transaction class, constrained addr/write/data |
| `apb_generator.sv` | Randomizes N transactions into a mailbox |
| `apb_driver.sv` | Drives transactions per the APB SETUP->ACCESS protocol |
| `apb_monitor.sv` | Passively samples the bus, reconstructs transactions |
| `apb_scoreboard.sv` | Reference model + self-checking comparison |
| `apb_coverage.sv` | Functional coverage via `covergroup`, cross coverage |
| `apb_env.sv` | Wires all components together, runs the test |
| `tb_top.sv` | Top-level for the class-based TB above |
| `tb_top_iverilog.sv` | Task/procedural re-implementation of the same methodology, written to avoid constructs that free/offline tools don't support (see below) |
| `my_simulation_log` | Raw ModelSim transcript — the actual run this project's results are based on |
| `modelsim_simulation_log.txt` | Annotated write-up of the same ModelSim run |
| `apb_tb.vcd` | Waveform dump from the ModelSim run |

## What was actually run

This project was verified on **ModelSim - Intel FPGA Edition, vlog/vsim 2020.1**
(the free edition bundled with Intel Quartus). That edition does not carry a
verification license, so loading the class-based OOP testbench
(`apb_transaction.sv` → `tb_top.sv`) fails with:

```
** Error: (vsim-1) Unable to checkout verification license -
testbench generation feature (randomize, randcase, randsequence,
covergroup) is only supported with QuestaSim.
```

That's a licensing restriction of the free edition, not a code defect — the
class-based files compile cleanly. To get a real, running simulation on this
tool, `tb_top_iverilog.sv` — a procedural version of the same methodology
(generator, driver, self-checking scoreboard with a reference model, manually
tracked coverage bins, weighted `$urandom` stimulus, no `constraint`/
`randomize()`/`covergroup`) — was compiled and run instead. This is the run
documented in `my_simulation_log` and `modelsim_simulation_log.txt`, and it's
the source of every result number in this README.

`tb_top_iverilog.sv` was also written to avoid Icarus-Verilog-unsupported
constructs, so it's *intended* to be portable to Icarus as well — but that
hasn't been independently re-verified in this repo, so no Icarus-specific
results are claimed here. If you run it on Icarus yourself, treat the exact
coverage counts as a fresh, independent seed run, not a reproduction of the
ModelSim numbers.

## How to run (ModelSim / Questa)

```bash
vlib work
vlog -sv apb_slave_dut.sv tb_top_iverilog.sv
vsim -c tb_top_iverilog -do "run -all; quit"
```

**Class-based version** (needs a Questa/VCS/Xcelium license, or EDA Playground):
```bash
vlib work
vlog -sv apb_slave_dut.sv apb_if.sv tb_top.sv
vsim -c tb_top -do "run -all; quit"
```
*(`tb_top.sv` includes the class files via `` `include ``, so you don't list them separately.)*

**Vivado xsim (class-based version):**
```bash
xvlog -sv apb_slave_dut.sv apb_if.sv tb_top.sv
xelab tb_top -s tb_sim
xsim tb_sim -runall
```

Output: pass/fail count from the scoreboard + a functional coverage summary,
plus `apb_tb.vcd` for waveform debug.

## Actual simulation results (ModelSim, `tb_top_iverilog.sv`)

```
SCOREBOARD REPORT: PASS=200 FAIL=0 TOTAL=200
FUNCTIONAL COVERAGE: 8 / 8 bins hit (100.0%)
RESULT: ALL TESTS PASSED
```

Full log: see `modelsim_simulation_log.txt` (annotated) and
`my_simulation_log` (raw tool transcript). It also documents a real
reference-model gap found and fixed during bring-up — see below.

## The 3 DUT quirks (why randomization matters here)

1. Register `0xF` (offset `0x3C`) is **read-only** — writes are silently dropped.
2. Any address **≥ 0x40** asserts `PSLVERR`.
3. Register `0x0`, when written with bit[31] set, **self-clears that bit
   two cycles later** — a classic "self-clearing control bit" register bug source.

A directed test with a handful of hand-picked addresses will likely never hit
all three. The constrained-random `target_special_reg` knob in
`apb_transaction.sv` biases toward these cases so they show up reliably
within ~200 transactions.

## Bug found and fixed during bring-up (good interview talking point)

The first ModelSim run using `tb_top_iverilog.sv` produced:

```
SCOREBOARD REPORT: PASS=193 FAIL=7 TOTAL=200
```

All 7 failures were reads of register 0 where the expected value had bit[31]
set but the DUT returned bit[31] = 0, e.g.:
```
FAIL: read mismatch addr=0x0 exp=0xa95ed63d got=0x295ed63d
```

Root cause: the scoreboard's reference model was a plain register mirror —
it didn't model register 0's documented 2-cycle self-clearing bit[31]
behavior. Since every APB transaction here takes 3 clock edges
(SETUP/ACCESS/sample), by the time any subsequent read transaction executes,
more than the DUT's 2-cycle self-clear delay has already elapsed. A directed
test (write reg0 with bit[31] set, then read reg0 on the very next
transaction) confirmed bit[31] always reads back as 0.

Fix: the reference model's read-check for register 0 now always masks bit[31]
to the expected value 0, regardless of what was last written. Re-verified:
200/200 pass, 8/8 coverage bins hit.

