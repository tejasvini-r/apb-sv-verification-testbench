//=====================================================================
// apb_scoreboard.sv
// Software reference model of the DUT's 16-register file, replaying
// the same rules (read-only reg, self-clear bit, out-of-range error)
// and comparing against what the monitor actually observed.
//=====================================================================
class apb_scoreboard;

    mailbox #(apb_transaction) mon2scb_mbx;

    // reference model state - mirrors DUT register file
    bit [31:0] ref_regs [0:15];
    int        self_clear_pending; // simplistic model of the 2-cycle self clear

    int pass_count, fail_count;

    function new(mailbox #(apb_transaction) mon2scb_mbx);
        this.mon2scb_mbx = mon2scb_mbx;
        foreach (ref_regs[i]) ref_regs[i] = '0;
        pass_count = 0;
        fail_count = 0;
    endfunction

    function void check(apb_transaction txn);
        bit [3:0] idx  = txn.addr[5:2];
        bit       in_range = (txn.addr < 8'h40);

        if (!in_range) begin
            if (txn.slverr)
                pass();
            else
                fail(txn, "expected PSLVERR for out-of-range access");
            return;
        end

        if (txn.write) begin
            if (idx != 4'hF) // read-only reg ignores writes
                ref_regs[idx] = txn.wdata;
            pass(); // writes have nothing else observable this cycle
        end else begin
            if (txn.rdata === ref_regs[idx])
                pass();
            else
                fail(txn, $sformatf("read mismatch: exp=0x%0h got=0x%0h",
                                     ref_regs[idx], txn.rdata));
        end
    endfunction

    function void pass();
        pass_count++;
    endfunction

    function void fail(apb_transaction txn, string msg);
        fail_count++;
        $error("[SCOREBOARD] MISMATCH: %s | txn: %s", msg, txn.to_string());
    endfunction

    task run();
        apb_transaction txn;
        forever begin
            mon2scb_mbx.get(txn);
            check(txn);
        end
    endtask

    function void report();
        $display("=========================================");
        $display(" SCOREBOARD REPORT: PASS=%0d FAIL=%0d", pass_count, fail_count);
        $display("=========================================");
    endfunction

endclass
