//=====================================================================
// apb_coverage.sv
// Functional coverage - this is what you show an interviewer to prove
// you understand coverage-driven verification, not just code coverage.
//=====================================================================
class apb_coverage;

    mailbox #(apb_transaction) mon2cov_mbx;
    apb_transaction txn;

    covergroup cg_apb;
        option.per_instance = 1;

        cp_write : coverpoint txn.write;

        cp_addr : coverpoint txn.addr {
            bins reg0        = {8'h00};
            bins normal_regs = {[8'h04:8'h38]};
            bins readonly_reg= {8'h3C};
            bins out_of_range= {[8'h40:8'hFF]};
        }

        cp_slverr : coverpoint txn.slverr;

        cross_write_addr : cross cp_write, cp_addr;

        cp_selfclear_bit : coverpoint txn.wdata[31] iff (txn.write && txn.addr == 8'h00);
    endgroup

    function new(mailbox #(apb_transaction) mon2cov_mbx);
        this.mon2cov_mbx = mon2cov_mbx;
        cg_apb = new();
    endfunction

    task run();
        forever begin
            mon2cov_mbx.get(txn);
            cg_apb.sample();
        end
    endtask

    function void report();
        $display("=========================================");
        $display(" FUNCTIONAL COVERAGE: %0.2f%%", cg_apb.get_coverage());
        $display("=========================================");
    endfunction

endclass
