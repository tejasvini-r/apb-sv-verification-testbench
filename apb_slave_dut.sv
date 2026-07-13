//=====================================================================
// apb_slave_dut.sv
// Simple APB Slave: 16 x 32-bit addressable registers
// Includes a couple of intentional quirks that a good randomized
// testbench (and NOT a directed one) is likely to catch:
//   1. Register 0xF (READ-ONLY status reg) ignores writes.
//   2. Writing to an out-of-range address sets PSLVERR.
//   3. Register 0x0 clears itself 2 cycles after being written with
//      bit[31] set (models a "self-clearing control bit" - classic
//      register bug source).
//=====================================================================
module apb_slave_dut #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    input  logic                    pclk,
    input  logic                    presetn,
    input  logic [ADDR_WIDTH-1:0]   paddr,
    input  logic                    pwrite,
    input  logic                    psel,
    input  logic                    penable,
    input  logic [DATA_WIDTH-1:0]   pwdata,
    output logic [DATA_WIDTH-1:0]   prdata,
    output logic                    pready,
    output logic                    pslverr
);

    localparam NUM_REGS = 16;
    logic [DATA_WIDTH-1:0] regs [0:NUM_REGS-1];
    logic [1:0] self_clear_cnt;

    wire [3:0] reg_idx = paddr[5:2]; // word-aligned decode
    wire       in_range = (paddr < (NUM_REGS*4));

    // APB FSM: single-cycle ready (no wait states) for simplicity
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            for (int i = 0; i < NUM_REGS; i++) regs[i] <= '0;
            prdata         <= '0;
            pslverr        <= 1'b0;
            self_clear_cnt <= '0;
        end else begin
            pslverr <= 1'b0;

            // self-clearing bit logic for reg0
            if (self_clear_cnt != 0) begin
                self_clear_cnt <= self_clear_cnt - 1;
                if (self_clear_cnt == 1)
                    regs[0][31] <= 1'b0;
            end

            if (psel && penable) begin
                if (!in_range) begin
                    pslverr <= 1'b1;
                end else if (pwrite) begin
                    if (reg_idx != 4'hF) begin // reg 0xF is read-only
                        regs[reg_idx] <= pwdata;
                        if (reg_idx == 0 && pwdata[31])
                            self_clear_cnt <= 2'd2;
                    end
                end else begin
                    prdata <= in_range ? regs[reg_idx] : '0;
                end
            end
        end
    end

    assign pready = 1'b1; // no wait-state slave

endmodule
