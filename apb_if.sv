//=====================================================================
// apb_if.sv
// APB interface with separate clocking blocks for driver (active) and
// monitor (passive) - this is the standard non-UVM way of avoiding
// race conditions between drive and sample.
//=====================================================================
interface apb_if #(parameter ADDR_WIDTH = 8, DATA_WIDTH = 32) (input logic pclk);

    logic                  presetn;
    logic [ADDR_WIDTH-1:0] paddr;
    logic                  pwrite;
    logic                  psel;
    logic                  penable;
    logic [DATA_WIDTH-1:0] pwdata;
    logic [DATA_WIDTH-1:0] prdata;
    logic                  pready;
    logic                  pslverr;

    // Driver drives on the clocking block to avoid race with DUT
    clocking drv_cb @(posedge pclk);
        default input #1step output #2;
        output paddr, pwrite, psel, penable, pwdata;
        input  prdata, pready, pslverr;
    endclocking

    // Monitor only samples - never drives
    clocking mon_cb @(posedge pclk);
        default input #1step;
        input paddr, pwrite, psel, penable, pwdata, prdata, pready, pslverr;
    endclocking

    modport DRIVER  (clocking drv_cb, input presetn);
    modport MONITOR (clocking mon_cb, input presetn);

endinterface
