//=====================================================================
// apb_driver.sv
// Pulls transactions from mailbox, drives them onto the DUT via the
// virtual interface following the APB SETUP -> ACCESS protocol.
//=====================================================================
class apb_driver;

    virtual apb_if.DRIVER vif;
    mailbox #(apb_transaction) gen2drv_mbx;
    int txn_count;

    function new(virtual apb_if.DRIVER vif, mailbox #(apb_transaction) gen2drv_mbx);
        this.vif = vif;
        this.gen2drv_mbx = gen2drv_mbx;
        this.txn_count = 0;
    endfunction

    task reset_dut();
        vif.drv_cb.psel    <= 0;
        vif.drv_cb.penable <= 0;
        vif.drv_cb.pwrite  <= 0;
        vif.drv_cb.paddr   <= 0;
        vif.drv_cb.pwdata  <= 0;
        repeat (3) @(vif.drv_cb);
    endtask

    task drive_txn(apb_transaction txn);
        // SETUP phase
        @(vif.drv_cb);
        vif.drv_cb.psel    <= 1;
        vif.drv_cb.penable <= 0;
        vif.drv_cb.paddr   <= txn.addr;
        vif.drv_cb.pwrite  <= txn.write;
        vif.drv_cb.pwdata  <= txn.write ? txn.wdata : '0;

        // ACCESS phase
        @(vif.drv_cb);
        vif.drv_cb.penable <= 1;

        @(vif.drv_cb);
        // pready is 1 always in this DUT; capture rdata for reads
        if (!txn.write)
            txn.rdata = vif.drv_cb.prdata;
        txn.slverr = vif.drv_cb.pslverr;

        // de-assert
        vif.drv_cb.psel    <= 0;
        vif.drv_cb.penable <= 0;
        txn_count++;
    endtask

    task run();
        apb_transaction txn;
        reset_dut();
        forever begin
            gen2drv_mbx.get(txn);
            drive_txn(txn);
        end
    endtask

endclass
