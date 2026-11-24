// Instruction memory (separate from data memory => no IF/MEM structural hazard).
// Program: parameter INIT_FILE (synthesis / FPGA) or +hex=file plusarg (simulation).
module imem #(parameter WORDS = 1024, parameter INIT_FILE = "") (
    input  [31:0] addr,
    output [31:0] rdata
);
    reg [31:0] mem [0:WORDS-1];
    integer i;
    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h00000013; // NOP
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
`ifndef SYNTHESIS
        begin : plusarg
            reg [1023:0] fname;
            if ($value$plusargs("hex=%s", fname)) $readmemh(fname, mem);
        end
`endif
    end
    assign rdata = mem[addr[$clog2(WORDS)+1:2]];
endmodule
