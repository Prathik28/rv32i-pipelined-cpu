// Instruction memory with a second (data-bus) port so programs can modify code (use FENCE.I).
// Separate from the data RAM => no IF/MEM structural hazard.
// Program: parameter INIT_FILE (synthesis / FPGA) or +hex=file plusarg (simulation).
module imem #(parameter WORDS = 1024, parameter INIT_FILE = "") (
    input         clk,
    // fetch port (async read)
    input  [31:0] addr,
    output [31:0] rdata,
    // data port (byte-enable write, async read)
    input         d_we,
    input  [3:0]  d_be,
    input  [31:0] d_addr,
    input  [31:0] d_wdata,
    output [31:0] d_rdata
);
    localparam AW = $clog2(WORDS);
    reg [7:0] b0 [0:WORDS-1];
    reg [7:0] b1 [0:WORDS-1];
    reg [7:0] b2 [0:WORDS-1];
    reg [7:0] b3 [0:WORDS-1];
    reg [31:0] init [0:WORDS-1];
    integer i;
    initial begin
        for (i = 0; i < WORDS; i = i + 1) init[i] = 32'h00000013; // NOP
        if (INIT_FILE != "") $readmemh(INIT_FILE, init);
`ifndef SYNTHESIS
        begin : plusarg
            reg [1023:0] fname;
            if ($value$plusargs("hex=%s", fname)) $readmemh(fname, init);
        end
`endif
        for (i = 0; i < WORDS; i = i + 1) {b3[i], b2[i], b1[i], b0[i]} = init[i];
    end

    wire [AW-1:0] fi = addr[AW+1:2];
    wire [AW-1:0] di = d_addr[AW+1:2];
    assign rdata   = {b3[fi], b2[fi], b1[fi], b0[fi]};
    assign d_rdata = {b3[di], b2[di], b1[di], b0[di]};

    always @(posedge clk) if (d_we) begin
        if (d_be[0]) b0[di] <= d_wdata[7:0];
        if (d_be[1]) b1[di] <= d_wdata[15:8];
        if (d_be[2]) b2[di] <= d_wdata[23:16];
        if (d_be[3]) b3[di] <= d_wdata[31:24];
    end
endmodule
