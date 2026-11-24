// Branch target buffer with 2-bit saturating counters.
// Looked up in IF (combinational), trained from EX when the real outcome is known.
//   * full tags => a hit always refers to that exact PC (no aliasing mispredictions)
//   * new entries are allocated only for taken branches/jumps, weakly-taken (2'b10)
module branch_predictor #(parameter ENTRIES = 16) (
    input         clk,
    input         rst,
    input  [31:0] lookup_pc,
    output        pred_taken,
    output [31:0] pred_target,
    input         upd_en,
    input  [31:0] upd_pc,
    input         upd_taken,
    input  [31:0] upd_target
);
    localparam IDXW = $clog2(ENTRIES);
    localparam TAGW = 30 - IDXW;

    reg [ENTRIES-1:0] valid;
    reg [TAGW-1:0]    tag    [0:ENTRIES-1];
    reg [31:0]        target [0:ENTRIES-1];
    reg [1:0]         ctr    [0:ENTRIES-1];

    wire [IDXW-1:0] li = lookup_pc[IDXW+1:2];
    wire [TAGW-1:0] lt = lookup_pc[31:IDXW+2];
    wire            lhit = valid[li] && (tag[li] == lt);
    assign pred_taken  = lhit && ctr[li][1];
    assign pred_target = target[li];

    wire [IDXW-1:0] ui = upd_pc[IDXW+1:2];
    wire [TAGW-1:0] ut = upd_pc[31:IDXW+2];
    wire            uhit = valid[ui] && (tag[ui] == ut);

    integer k;
    initial for (k = 0; k < ENTRIES; k = k + 1) begin
        tag[k] = 0; target[k] = 0; ctr[k] = 0;
    end

    always @(posedge clk) begin
        if (rst) valid <= {ENTRIES{1'b0}};
        else if (upd_en) begin
            if (uhit) begin
                if (upd_taken) begin
                    if (ctr[ui] != 2'b11) ctr[ui] <= ctr[ui] + 2'b01;
                    target[ui] <= upd_target;
                end else if (ctr[ui] != 2'b00) ctr[ui] <= ctr[ui] - 2'b01;
            end else if (upd_taken) begin
                valid[ui] <= 1'b1; tag[ui] <= ut; target[ui] <= upd_target; ctr[ui] <= 2'b10;
            end
        end
    end
endmodule
