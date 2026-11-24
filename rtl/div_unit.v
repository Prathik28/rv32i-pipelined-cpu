// Iterative restoring divider (32 cycles) for DIV, DIVU, REM, REMU (funct3[1:0] = 00,01,10,11).
// Operands are latched on `start`, so the pipeline may keep changing forwarding sources.
// Handles divide-by-zero and signed overflow per the RISC-V spec.
module div_unit (
    input         clk,
    input         rst,
    input         en,            // 0 = freeze (pipeline held by a memory wait state)
    input         start,
    input  [31:0] a,
    input  [31:0] b,
    input  [1:0]  op,
    output reg    active,
    output reg    done,          // one-cycle pulse: result valid
    output [31:0] result
);
    reg [31:0] q, r, dvs, special;
    reg [5:0]  cnt;
    reg        neg_q, neg_r, use_special, is_rem;

    wire sgn       = ~op[0];
    wire a_neg     = sgn & a[31];
    wire b_neg     = sgn & b[31];
    wire [31:0] am = a_neg ? -a : a;
    wire [31:0] bm = b_neg ? -b : b;
    wire by_zero   = (b == 32'b0);
    wire overflow  = sgn && (a == 32'h8000_0000) && (b == 32'hFFFF_FFFF);

    wire [32:0] r_sh   = {r[31:0], q[31]};
    wire        ge     = (r_sh >= {1'b0, dvs});
    wire [32:0] r_next = ge ? (r_sh - {1'b0, dvs}) : r_sh;

    always @(posedge clk) begin
        if (en || rst) done <= 1'b0;
        if (rst) begin
            active <= 0; done <= 0; cnt <= 0; use_special <= 0;
        end else if (!en) begin
            ;
        end else if (start) begin
            is_rem <= op[1];
            if (by_zero) begin
                use_special <= 1; special <= op[1] ? a : 32'hFFFF_FFFF; done <= 1;
            end else if (overflow) begin
                use_special <= 1; special <= op[1] ? 32'b0 : 32'h8000_0000; done <= 1;
            end else begin
                use_special <= 0; active <= 1; cnt <= 0;
                q <= am; r <= 32'b0; dvs <= bm;
                neg_q <= a_neg ^ b_neg; neg_r <= a_neg;
            end
        end else if (active) begin
            r   <= r_next[31:0];
            q   <= {q[30:0], ge};
            cnt <= cnt + 1;
            if (cnt == 6'd31) begin active <= 0; done <= 1; end
        end
    end

    wire [31:0] quo = neg_q ? -q : q;
    wire [31:0] rem = neg_r ? -r : r;
    assign result = use_special ? special : (is_rem ? rem : quo);
endmodule
