// Instruction memory (read-only, async). Program: parameter INIT_FILE or +hex=file plusarg.
module mips_imem #(parameter WORDS = 1024, parameter INIT_FILE = "") (
    input  [31:0] addr,
    output [31:0] rdata
);
    reg [31:0] mem [0:WORDS-1];
    integer i;
    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h00000000;   // NOP (sll $0,$0,0)
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
