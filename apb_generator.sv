//=====================================================================
// apb_generator.sv
// Randomizes transactions and pushes them into the driver mailbox.
//=====================================================================
class apb_generator;

    mailbox #(apb_transaction) gen2drv_mbx;
    int num_txns;
    event done;

    function new(mailbox #(apb_transaction) gen2drv_mbx, int num_txns);
        this.gen2drv_mbx = gen2drv_mbx;
        this.num_txns    = num_txns;
    endfunction

    task run();
        apb_transaction txn;
        for (int i = 0; i < num_txns; i++) begin
            txn = new();
            if (!txn.randomize())
                $fatal("Generator: randomize failed on txn %0d", i);
            gen2drv_mbx.put(txn);
        end
        -> done;
    endtask

endclass
