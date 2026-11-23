// Data memory: async read, synchronous byte-enable write.
module dmem #(parameter WORDS = 1024) (
    input         clk,
    input         we,
    input  [3:0]  be,
    input  [31:0] addr,
    input  [31:0] wdata,
    output [31:0] rdata
);
    reg [31:0] mem [0:WORDS-1];
    integer i;
    initial for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'b0;

    wire [$clog2(WORDS)-1:0] idx = addr[$clog2(WORDS)+1:2];
    wire [31:0] mask = {{8{be[3]}}, {8{be[2]}}, {8{be[1]}}, {8{be[0]}}};

    assign rdata = mem[idx];
    always @(posedge clk)
        if (we) mem[idx] <= (mem[idx] & ~mask) | (wdata & mask);
endmodule
