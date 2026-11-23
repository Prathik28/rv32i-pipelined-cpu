// Instruction memory (separate from data memory => no IF/MEM structural hazard)
// Load a program with:  vvp sim +hex=prog.hex
module imem #(parameter WORDS = 1024) (
    input  [31:0] addr,
    output [31:0] rdata
);
    reg [31:0] mem [0:WORDS-1];
    reg [1023:0] fname;
    integer i;
    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h00000013; // NOP
        if ($value$plusargs("hex=%s", fname)) $readmemh(fname, mem);
    end
    assign rdata = mem[addr[$clog2(WORDS)+1:2]];
endmodule
