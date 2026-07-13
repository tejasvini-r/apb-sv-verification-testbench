//=====================================================================
// apb_transaction.sv
// The "packet" that flows Generator -> Driver, and Monitor -> Scoreboard
//=====================================================================
class apb_transaction;

    rand bit [7:0]  addr;
    rand bit        write;   // 1 = write, 0 = read
    rand bit [31:0] wdata;
         bit [31:0] rdata;   // filled in by driver/monitor after the txn
         bit        slverr;

    // knobs to bias interesting scenarios
    rand bit        target_special_reg; // hit reg0 / reg0xF / out-of-range more often

    constraint c_addr_dist {
        target_special_reg dist {1 := 30, 0 := 70};
        if (target_special_reg) {
            addr inside {8'h00, 8'h3C, 8'h40, 8'h44}; // reg0, reg0xF(0x3C), out-of-range
        } else {
            addr inside {[8'h00:8'h3C]};
            addr[1:0] == 2'b00; // word aligned
        }
    }

    constraint c_write_dist { write dist {1 := 50, 0 := 50}; }

    function void post_randomize();
        addr = addr & 8'hFC; // enforce word alignment always
    endfunction

    function string to_string();
        return $sformatf("addr=0x%0h write=%0d wdata=0x%0h rdata=0x%0h slverr=%0b",
                          addr, write, wdata, rdata, slverr);
    endfunction

    function apb_transaction clone();
        apb_transaction t = new();
        t.addr   = this.addr;
        t.write  = this.write;
        t.wdata  = this.wdata;
        t.rdata  = this.rdata;
        t.slverr = this.slverr;
        return t;
    endfunction

endclass
