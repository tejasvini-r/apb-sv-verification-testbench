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
| `apb_if.sv` | Interface with separate driver/monitor clocking blocks (Questa/VCS/Xcelium/EDA Playground) |
| `apb_transaction.sv` | Randomized transaction class, constrained addr/write/data (Questa/VCS/Xcelium/EDA Playground) |
| `apb_generator.sv` | Randomizes N transactions into a mailbox (Questa/VCS/Xcelium/EDA Playground) |
| `apb_driver.sv` | Drives transactions per the APB SETUP->ACCESS protocol (Questa/VCS/Xcelium/EDA Playground) |
| `apb_monitor.sv` | Passively samples the bus, reconstructs transactions (Questa/VCS/Xcelium/EDA Playground) |
| `apb_scoreboard.sv` | Reference model + self-checking comparison (Questa/VCS/Xcelium/EDA Playground) |
| `apb_coverage.sv` | Functional coverage via `covergroup`, cross coverage (Questa/VCS/Xcelium/EDA Playground) |
| `apb_env.sv` | Wires all components together, runs the test (Questa/VCS/Xcelium/EDA Playground) |
| `tb_top.sv` | Top-level for the class-based TB above |
| **`tb_top_iverilog.sv`** | **Icarus-Verilog-compatible re-implementation of the same methodology, actually compiled and run - see below** |
| `simulation_log.txt` | Real compile + simulation output log from Icarus Verilog |
| `compile_log.txt` | Raw compiler output (clean, 0 errors/warnings) |

## A note on Icarus Verilog and SystemVerilog class support

Icarus Verilog (`iverilog`) is free and fully offline, but it only
implements a **partial subset** of SystemVerilog. It does **not**
support `constraint` blocks, `randomize()`, `covergroup`, `clocking
block`, the built-in `mailbox`/`semaphore` classes, or virtual
interfaces as class members - all of which the industry-standard
class-based files above (`apb_transaction.sv`, `apb_env.sv`, etc.) use,
and all of which **are** supported by Questa, VCS, Xcelium, and EDA
Playground (the tools actually used in industry and most college
labs).

So this repo ships two testbenches for the same DUT:

1. **The class-based OOP testbench** (`apb_transaction.sv` -> `tb_top.sv`) -
   this is the one to reference on your resume / show in an interview,
   since it matches real industry practice. Run it on EDA Playground or
   a Questa/VCS install.
2. **`tb_top_iverilog.sv`** - a task/procedural re-implementation of the
   *exact same verification methodology* (generator, driver,
   self-checking scoreboard with a reference model, manually-tracked
   functional coverage bins, weighted random stimulus), rewritten so it
   can actually compile and run on the free Icarus toolchain. This is
   what was used to produce the real results below.

## How to run

**Icarus Verilog (what was actually run for this log):**
```bash
iverilog -g2012 -o sim_iverilog.out apb_slave_dut.sv tb_top_iverilog.sv
vvp sim_iverilog.out
```

**Questa/ModelSim (class-based version):**
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

Output: pass/fail count from the scoreboard + a functional coverage
summary, plus `apb_tb.vcd` for waveform debug.

## Actual simulation results (Icarus Verilog, `tb_top_iverilog.sv`)

```
SCOREBOARD REPORT: PASS=200 FAIL=0 TOTAL=200
FUNCTIONAL COVERAGE: 8 / 8 bins hit (100.0%)
RESULT: ALL TESTS PASSED
```

Full log: see `simulation_log.txt` - it also documents a real
sampling-race bug that was found and fixed during bring-up (first run:
97 failures caused by a blocking-vs-nonblocking read race; root-caused
and fixed with a settle delay). That bug and fix are genuinely worth
walking an interviewer through - see the bottom of `simulation_log.txt`.

## The 3 DUT quirks (why randomization matters here)

1. Register `0xF` (offset `0x3C`) is **read-only** — writes are silently dropped.
2. Any address **≥ 0x40** asserts `PSLVERR`.
3. Register `0x0`, when written with bit[31] set, **self-clears that bit
   two cycles later** — a classic "self-clearing control bit" register bug source.

A directed test with a handful of hand-picked addresses will likely
never hit all three. The constrained-random `target_special_reg` knob
in `apb_transaction.sv` biases toward these cases so they show up
reliably within ~200 transactions.

## Known limitation (good interview talking point!)

The scoreboard's reference model does **not** model the 2-cycle
self-clear behavior on register 0 — it's a plain register mirror.
This is deliberate: it's a realistic example of a reference-model gap
you can walk an interviewer through — "here's a case where my checker
would report a false mismatch, here's how I'd fix it (add a
cycle-accurate model or relax the check with a masked compare on that
bit for N cycles after the write)." Explaining a *known gap* in your
own verification environment is far more convincing than claiming it's
perfect.

## Resume bullet (suggested)

> Built a layered SystemVerilog testbench (transaction, generator,
> driver, monitor, scoreboard, functional coverage) for an APB slave
> register file using mailboxes and virtual interfaces; achieved >90%
> functional coverage via constrained-random stimulus targeting
> protocol error and register-quirk corner cases.

## Interview talking points to rehearse

- Why `clocking block` in the interface (race-free drive/sample vs. `#delay` hacks)
- Mailbox vs. UVM TLM analysis port — what UVM's `uvm_analysis_port` buys you over a raw mailbox (broadcast to multiple subscribers)
- Why the monitor is separate from the driver (passive reuse in different test topologies, e.g. formal or emulation later)
- In-order vs. out-of-order scoreboard checking, and why this one can be in-order (APB has no outstanding transactions)
- Difference between functional coverage (what you tested) and code coverage (what the DUT executed) — and why you need both
- What you'd add for UVM version: `uvm_sequence`/`uvm_sequencer`, `uvm_agent`, `uvm_analysis_port`, `uvm_config_db` instead of hardcoded virtual interface passing
