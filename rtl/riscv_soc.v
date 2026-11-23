// Core + separate instruction / data memories
module riscv_soc (
    input         clk,
    input         rst,
    output        halt,
    output [31:0] perf_cycles,
    output [31:0] perf_instret,
    output [31:0] perf_stalls,
    output [31:0] perf_flushes
);
    wire [31:0] imem_addr, imem_rdata;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_be;
    wire        dmem_we;

    riscv_core u_core (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_be(dmem_be),
        .dmem_we(dmem_we), .dmem_rdata(dmem_rdata),
        .halt(halt), .perf_cycles(perf_cycles), .perf_instret(perf_instret),
        .perf_stalls(perf_stalls), .perf_flushes(perf_flushes)
    );
    imem u_imem (.addr(imem_addr), .rdata(imem_rdata));
    dmem u_dmem (.clk(clk), .we(dmem_we), .be(dmem_be), .addr(dmem_addr),
                 .wdata(dmem_wdata), .rdata(dmem_rdata));
endmodule
