//=====================================================================
// tb_top_iverilog.sv
// ICARUS-VERILOG-COMPATIBLE VERSION of the APB layered testbench.
//
// WHY THIS FILE EXISTS:
// Icarus Verilog (iverilog) implements only a partial subset of
// SystemVerilog. It does NOT support: constraint blocks, randomize(),
// covergroups, clocking blocks, mailbox/semaphore classes, or virtual
// interfaces as class members. Those ARE supported by the commercial
// simulators used in industry (Questa, VCS, Xcelium) and by EDA
// Playground - which is what the class-based files in this repo
// (apb_transaction.sv, apb_generator.sv, apb_driver.sv, apb_monitor.sv,
// apb_scoreboard.sv, apb_coverage.sv, apb_env.sv) are written for and
// were designed against.
//
// This file re-implements the SAME verification methodology
// (generator, driver, monitor, self-checking scoreboard, functional
// coverage bins, constrained-random stimulus, corner-case biasing)
// using tasks and procedural code instead of classes, purely so it
// can be compiled and run end-to-end on the free, offline Icarus
// Verilog toolchain and produce a real simulation log.
//=====================================================================

module tb_top_iverilog;

    // ---------------------------------------------------------------
    // Clock / reset
    // ---------------------------------------------------------------
    logic pclk;
    logic presetn;

    initial pclk = 0;
    always #5 pclk = ~pclk;

    // ---------------------------------------------------------------
    // DUT signals
    // ---------------------------------------------------------------
    logic [7:0]  paddr;
    logic        pwrite;
    logic        psel;
    logic        penable;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;

    apb_slave_dut #(.ADDR_WIDTH(8), .DATA_WIDTH(32)) dut (
        .pclk    (pclk),
        .presetn (presetn),
        .paddr   (paddr),
        .pwrite  (pwrite),
        .psel    (psel),
        .penable (penable),
        .pwdata  (pwdata),
        .prdata  (prdata),
        .pready  (pready),
        .pslverr (pslverr)
    );

    // ---------------------------------------------------------------
    // Reference model (mirrors DUT register file for scoreboarding)
    // ---------------------------------------------------------------
    logic [31:0] ref_regs [0:15];

    // ---------------------------------------------------------------
    // Bookkeeping
    // ---------------------------------------------------------------
    int pass_count   = 0;
    int fail_count   = 0;
    int total_txns   = 0;

    // functional coverage bins (manual, since covergroup unsupported)
    int cov_reg0_hits        = 0;
    int cov_normal_reg_hits  = 0;
    int cov_readonly_hits    = 0;
    int cov_oob_hits         = 0;
    int cov_write_count      = 0;
    int cov_read_count       = 0;
    int cov_selfclear_bit_set= 0;
    int cov_pslverr_seen     = 0;

    // ---------------------------------------------------------------
    // Driver task: performs one APB SETUP->ACCESS transfer
    // ---------------------------------------------------------------
    task automatic apb_transfer(
        input  logic [7:0]  addr,
        input  logic        write,
        input  logic [31:0] wdata,
        output logic [31:0] rdata_out,
        output logic        slverr_out
    );
        @(posedge pclk);
        psel    <= 1;
        penable <= 0;
        paddr   <= addr;
        pwrite  <= write;
        pwdata  <= write ? wdata : '0;

        @(posedge pclk);
        penable <= 1;

        @(posedge pclk);
        #1; // let the DUT's nonblocking (NBA) update to prdata/pslverr settle
            // before sampling - without this delay there is a classic
            // read-before-write race (this is exactly the race that SV
            // 'clocking block' input skew, e.g. "input #1step", exists to
            // prevent in the class-based/clocking-block version of this TB)
        rdata_out  = prdata;
        slverr_out = pslverr;

        psel    <= 0;
        penable <= 0;
    endtask

    // ---------------------------------------------------------------
    // Reference-model check (same rules as the DUT, including the
    // register-0 self-clearing bit[31] behavior - see the masking
    // logic in the read branch below for how the timing is modeled)
    // ---------------------------------------------------------------
    task automatic check_txn(
        input logic [7:0]  addr,
        input logic        write,
        input logic [31:0] wdata,
        input logic [31:0] rdata,
        input logic        slverr
    );
        logic [3:0] idx;
        logic       in_range;
        idx      = addr[5:2];
        in_range = (addr < 8'h40);

        total_txns++;
        if (write) cov_write_count++; else cov_read_count++;
        if (slverr) cov_pslverr_seen++;

        if (addr == 8'h00)        cov_reg0_hits++;
        else if (addr == 8'h3C)   cov_readonly_hits++;
        else if (!in_range)       cov_oob_hits++;
        else                      cov_normal_reg_hits++;

        if (write && addr == 8'h00 && wdata[31]) cov_selfclear_bit_set++;

        if (!in_range) begin
            if (slverr) begin
                pass_count++;
            end else begin
                fail_count++;
                $display("[%0t] FAIL: expected PSLVERR for out-of-range addr=0x%0h", $time, addr);
            end
        end else if (write) begin
            if (idx != 4'hF) // read-only reg ignores writes
                ref_regs[idx] = wdata;
            pass_count++;
        end else begin
            logic [31:0] expected;
            expected = ref_regs[idx];
            // Register 0 bit[31] self-clears 2 cycles after being written
            // with bit[31] set. Every APB transaction here takes 3 clock
            // edges (SETUP/ACCESS/sample), so by the time ANY subsequent
            // read transaction occurs, at least one full extra transaction
            // (>= 3 clock edges) has elapsed since the write's ACCESS edge -
            // more than enough for the 2-cycle self-clear to have already
            // completed on real hardware. So a read of reg0 must always
            // expect bit[31] == 0, regardless of what was last written.
            if (idx == 4'h0)
                expected[31] = 1'b0;

            if (rdata === expected) begin
                pass_count++;
            end else begin
                fail_count++;
                $display("[%0t] FAIL: read mismatch addr=0x%0h exp=0x%0h got=0x%0h",
                          $time, addr, expected, rdata);
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Constrained-random-style address generator (manual, replicates
    // the weighted 'target_special_reg dist' constraint from
    // apb_transaction.sv using $urandom_range since Icarus has no
    // 'dist'/'constraint' support)
    // ---------------------------------------------------------------
    function automatic logic [7:0] gen_addr();
        int pick;
        int special_pick;
        pick = $urandom_range(0, 99);
        if (pick < 30) begin
            // 30% of the time: hit a "special" address, matching the
            // {reg0, readonly_reg(0x3C), out-of-range(0x40/0x44)} set
            special_pick = $urandom_range(0, 3);
            case (special_pick)
                0: gen_addr = 8'h00;
                1: gen_addr = 8'h3C;
                2: gen_addr = 8'h40;
                3: gen_addr = 8'h44;
            endcase
        end else begin
            // 70%: normal word-aligned address in range
            gen_addr = {$urandom_range(0, 15), 2'b00};
        end
    endfunction

    // ---------------------------------------------------------------
    // Main stimulus
    // ---------------------------------------------------------------
    logic [31:0] rdata_capture;
    logic        slverr_capture;
    logic [7:0]  addr_capture;
    logic        write_capture;
    logic [31:0] wdata_capture;

    initial begin
        int i;

        for (i = 0; i < 16; i++) ref_regs[i] = '0;

        psel    = 0;
        penable = 0;
        pwrite  = 0;
        paddr   = 0;
        pwdata  = 0;
        presetn = 0;
        repeat (5) @(posedge pclk);
        presetn = 1;
        repeat (3) @(posedge pclk);

        $display("=========================================");
        $display(" APB Layered TB (Icarus-compatible) START");
        $display("=========================================");

        for (i = 0; i < 200; i++) begin
            addr_capture  = gen_addr();
            write_capture = $urandom_range(0, 1);
            wdata_capture = $urandom;

            apb_transfer(addr_capture, write_capture, wdata_capture,
                         rdata_capture, slverr_capture);

            check_txn(addr_capture, write_capture, wdata_capture,
                     rdata_capture, slverr_capture);
        end

        // drain
        repeat (10) @(posedge pclk);

        $display("=========================================");
        $display(" SCOREBOARD REPORT: PASS=%0d FAIL=%0d TOTAL=%0d",
                  pass_count, fail_count, total_txns);
        $display("=========================================");
        $display(" FUNCTIONAL COVERAGE (manual bins)");
        $display("   reg0 hits          : %0d %s", cov_reg0_hits,        (cov_reg0_hits>0)?"[HIT]":"[MISS]");
        $display("   normal_regs hits   : %0d %s", cov_normal_reg_hits,  (cov_normal_reg_hits>0)?"[HIT]":"[MISS]");
        $display("   readonly_reg hits  : %0d %s", cov_readonly_hits,    (cov_readonly_hits>0)?"[HIT]":"[MISS]");
        $display("   out_of_range hits  : %0d %s", cov_oob_hits,         (cov_oob_hits>0)?"[HIT]":"[MISS]");
        $display("   write ops          : %0d %s", cov_write_count,      (cov_write_count>0)?"[HIT]":"[MISS]");
        $display("   read ops           : %0d %s", cov_read_count,       (cov_read_count>0)?"[HIT]":"[MISS]");
        $display("   selfclear bit set  : %0d %s", cov_selfclear_bit_set,(cov_selfclear_bit_set>0)?"[HIT]":"[MISS]");
        $display("   PSLVERR observed   : %0d %s", cov_pslverr_seen,     (cov_pslverr_seen>0)?"[HIT]":"[MISS]");
        $display("=========================================");
        begin
            int bins_hit;
            bins_hit = (cov_reg0_hits>0) + (cov_normal_reg_hits>0) + (cov_readonly_hits>0) +
                       (cov_oob_hits>0) + (cov_write_count>0) + (cov_read_count>0) +
                       (cov_selfclear_bit_set>0) + (cov_pslverr_seen>0);
            $display(" COVERAGE: %0d / 8 bins hit (%0.1f%%)", bins_hit, (bins_hit*100.0)/8.0);
        end
        $display("=========================================");

        if (fail_count == 0)
            $display(" RESULT: ALL TESTS PASSED");
        else
            $display(" RESULT: %0d TEST(S) FAILED", fail_count);

        $display("=========================================");
        $finish;
    end

    // waveform dump
    initial begin
        $dumpfile("apb_tb.vcd");
        $dumpvars(0, tb_top_iverilog);
    end

endmodule






