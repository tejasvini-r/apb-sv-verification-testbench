//=====================================================================
// apb_env.sv
// Instantiates and connects generator, driver, monitor, scoreboard,
// and coverage. This is the layer UVM would call an "agent + env" -
// here it's just plain classes and mailboxes, which is exactly the
// point: you can explain every wire of connectivity in an interview.
//=====================================================================
class apb_env;

    virtual apb_if vif;

    mailbox #(apb_transaction) gen2drv_mbx;
    mailbox #(apb_transaction) mon2scb_mbx;
    mailbox #(apb_transaction) mon2cov_mbx;

    apb_generator   gen;
    apb_driver      drv;
    apb_monitor     mon;
    apb_scoreboard  scb;
    apb_coverage    cov;

    function new(virtual apb_if vif, int num_txns);
        this.vif = vif;

        gen2drv_mbx = new();
        mon2scb_mbx = new();
        mon2cov_mbx = new();

        gen = new(gen2drv_mbx, num_txns);
        drv = new(vif.DRIVER, gen2drv_mbx);
        mon = new(vif.MONITOR, mon2scb_mbx, mon2cov_mbx);
        scb = new(mon2scb_mbx);
        cov = new(mon2cov_mbx);
    endfunction

    task run();
        fork
            drv.run();
            mon.run();
            scb.run();
            cov.run();
        join_none

        gen.run(); // blocks until all txns generated
        wait (gen.done.triggered);

        // drain time for last txn to finish driving/checking
        repeat (10) @(posedge vif.pclk);

        scb.report();
        cov.report();
        $finish;
    endtask

endclass
