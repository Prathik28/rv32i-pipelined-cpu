// Physical memory protection check (4 entries, modes OFF / TOR / NA4 / NAPOT, lock bit).
// `lo`..`hi` are the first and last byte addresses of the access. Rules:
//   * lowest-numbered entry that matches any byte decides
//   * an access that only partly matches an entry fails (except M-mode on unlocked entries)
//   * no match: M-mode passes, U-mode fails
module pmp_check (
    input  [1:0]   priv,
    input  [31:0]  cfg,
    input  [127:0] pa,
    input  [31:0]  lo,
    input  [31:0]  hi,
    output         r_ok,
    output         w_ok,
    output         x_ok
);
    wire [29:0] wl = lo[31:2];
    wire [29:0] wh = hi[31:2];

    reg [29:0] pv [0:4];                 // pv[0] = 0 (TOR base of entry 0), pv[i+1] = pmpaddr[i]
    reg [7:0]  c, sel_cfg;
    reg        found, sel_full, ml, mh;
    reg [29:0] m;
    integer i;

    always @* begin
        pv[0] = 30'b0;
        for (i = 0; i < 4; i = i + 1) pv[i+1] = pa[32*i +: 30];
        found = 1'b0; sel_cfg = 8'b0; sel_full = 1'b0; ml = 1'b0; mh = 1'b0; m = 30'b0; c = 8'b0;
        for (i = 0; i < 4; i = i + 1) begin
            c = cfg[8*i +: 8];
            case (c[4:3])
                2'b01: begin ml = (wl >= pv[i]) && (wl < pv[i+1]);
                             mh = (wh >= pv[i]) && (wh < pv[i+1]); end
                2'b10: begin ml = (wl == pv[i+1]); mh = (wh == pv[i+1]); end
                2'b11: begin m  = ~(pv[i+1] ^ (pv[i+1] + 30'd1));
                             ml = (((wl ^ pv[i+1]) & m) == 30'b0);
                             mh = (((wh ^ pv[i+1]) & m) == 30'b0); end
                default: begin ml = 1'b0; mh = 1'b0; end
            endcase
            if (!found && (ml | mh)) begin found = 1'b1; sel_cfg = c; sel_full = ml & mh; end
        end
    end

    wire m_mode    = (priv == 2'b11);
    wire allow_all = m_mode & (~found | ~sel_cfg[7]);
    wire hit       = found & sel_full;
    assign r_ok = allow_all | (hit & sel_cfg[0]);
    assign w_ok = allow_all | (hit & sel_cfg[1]);
    assign x_ok = allow_all | (hit & sel_cfg[2]);
endmodule
