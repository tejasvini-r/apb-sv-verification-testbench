//=====================================================================
// apb_monitor.sv
// Passively watches the bus and reconstructs completed transactions,
// forwarding them to the scoreboard AND the coverage collector.
//=====================================================================
class apb_monitor;

    virtual apb_if.MONITOR vif;
    mailbox #(apb_transaction) mon2scb_mbx;
    mailbox #(apb_transaction) mon2cov_mbx;

    function new(virtual apb_if.MONITOR vif,
                 mailbox #(apb_transaction) mon2scb_mbx,
                 mailbox #(apb_transaction) mon2cov_mbx);
        this.vif = vif;
        this.mon2scb_mbx = mon2scb_mbx;
        this.mon2cov_mbx = mon2cov_mbx;
    endfunction

    task run();
        apb_transaction txn;
        forever begin
            // wait for ACCESS phase (psel & penable both high)
            @(vif.mon_cb);
            if (vif.mon_cb.psel && vif.mon_cb.penable) begin
                txn = new();
                txn.addr   = vif.mon_cb.paddr;
                txn.write  = vif.mon_cb.pwrite;
                txn.wdata  = vif.mon_cb.pwdata;
                txn.rdata  = vif.mon_cb.prdata;
                txn.slverr = vif.mon_cb.pslverr;

                mon2scb_mbx.put(txn.clone());
                mon2cov_mbx.put(txn.clone());
            end
        end
    endtask

endclass
