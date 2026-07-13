//=====================================================================
// tb_top.sv
// Top-level: clock/reset generation, DUT + interface instantiation,
// and kickoff of the environment. Compile this file last (or use a
// filelist) so all class files are parsed first.
//=====================================================================
`include "apb_transaction.sv"
`include "apb_generator.sv"
`include "apb_driver.sv"
`include "apb_monitor.sv"
`include "apb_scoreboard.sv"
`include "apb_coverage.sv"
`include "apb_env.sv"

module tb_top;

    logic pclk;
    logic presetn;

    // clock: 10ns period
    initial pclk = 0;
    always #5 pclk = ~pclk;

    apb_if #(.ADDR_WIDTH(8), .DATA_WIDTH(32)) apb_if_inst (.pclk(pclk));

    apb_slave_dut #(.ADDR_WIDTH(8), .DATA_WIDTH(32)) dut (
        .pclk    (pclk),
        .presetn (apb_if_inst.presetn),
        .paddr   (apb_if_inst.paddr),
        .pwrite  (apb_if_inst.pwrite),
        .psel    (apb_if_inst.psel),
        .penable (apb_if_inst.penable),
        .pwdata  (apb_if_inst.pwdata),
        .prdata  (apb_if_inst.prdata),
        .pready  (apb_if_inst.pready),
        .pslverr (apb_if_inst.pslverr)
    );

    initial begin
        apb_if_inst.presetn = 0;
        repeat (5) @(posedge pclk);
        apb_if_inst.presetn = 1;
    end

    apb_env env;

    initial begin
        // wait for reset deassertion before starting the environment
        wait (apb_if_inst.presetn === 1);
        env = new(apb_if_inst, 200); // 200 randomized transactions
        env.run();
    end

    // waveform dump
    initial begin
        $dumpfile("apb_tb.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
