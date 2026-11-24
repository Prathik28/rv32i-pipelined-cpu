// Data memory: async read, synchronous byte-enable write.
// Written as four byte lanes so synthesis tools infer (distributed / block) RAM.
module dmem #(parameter WORDS = 1024) (
    input         clk,
    input         we,
    input  [3:0]  be,
    input  [31:0] addr,
    input  [31:0] wdata,
    output [31:0] rdata
);
    reg [7:0] b0 [0:WORDS-1];
    reg [7:0] b1 [0:WORDS-1];
    reg [7:0] b2 [0:WORDS-1];
    reg [7:0] b3 [0:WORDS-1];
    integer i;
    initial for (i = 0; i < WORDS; i = i + 1) begin
        b0[i] = 8'b0; b1[i] = 8'b0; b2[i] = 8'b0; b3[i] = 8'b0;
    end

    wire [$clog2(WORDS)-1:0] idx = addr[$clog2(WORDS)+1:2];
    assign rdata = {b3[idx], b2[idx], b1[idx], b0[idx]};

    always @(posedge clk) if (we) begin
        if (be[0]) b0[idx] <= wdata[7:0];
        if (be[1]) b1[idx] <= wdata[15:8];
        if (be[2]) b2[idx] <= wdata[23:16];
        if (be[3]) b3[idx] <= wdata[31:24];
    end
endmodule
