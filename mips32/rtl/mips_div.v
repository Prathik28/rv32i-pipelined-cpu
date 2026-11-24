// Iterative 32-cycle divider for DIV / DIVU. Produces quotient (-> LO) and remainder (-> HI).
// MIPS leaves divide-by-zero UNPREDICTABLE; this implementation defines it as
//   quotient = 0xFFFFFFFF, remainder = dividend   (and INT_MIN / -1 = INT_MIN, remainder 0).
module mips_div (
    input         clk,
    input         rst,
    input         start,
    input  [31:0] a,
    input  [31:0] b,
    input         is_signed,
    output reg    active,
    output reg    done,          // one-cycle pulse: results valid
    output [31:0] quo,
    output [31:0] rem
);
    reg [31:0] q, r, dvs, sp_q, sp_r;
    reg [5:0]  cnt;
    reg        neg_q, neg_r, use_special;

    wire a_neg    = is_signed & a[31];
    wire b_neg    = is_signed & b[31];
    wire [31:0] am = a_neg ? -a : a;
    wire [31:0] bm = b_neg ? -b : b;
    wire by_zero  = (b == 32'b0);
    wire overflow = is_signed && (a == 32'h8000_0000) && (b == 32'hFFFF_FFFF);

    wire [32:0] r_sh   = {r[31:0], q[31]};
    wire        ge     = (r_sh >= {1'b0, dvs});
    wire [32:0] r_next = ge ? (r_sh - {1'b0, dvs}) : r_sh;

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            active <= 0; done <= 0; cnt <= 0; use_special <= 0;
        end else if (start) begin
            if (by_zero)       begin use_special <= 1; sp_q <= 32'hFFFF_FFFF; sp_r <= a;       done <= 1; end
            else if (overflow) begin use_special <= 1; sp_q <= 32'h8000_0000; sp_r <= 32'b0;   done <= 1; end
            else begin
                use_special <= 0; active <= 1; cnt <= 0;
                q <= am; r <= 32'b0; dvs <= bm; neg_q <= a_neg ^ b_neg; neg_r <= a_neg;
            end
        end else if (active) begin
            r <= r_next[31:0]; q <= {q[30:0], ge}; cnt <= cnt + 1;
            if (cnt == 6'd31) begin active <= 0; done <= 1; end
        end
    end

    assign quo = use_special ? sp_q : (neg_q ? -q : q);
    assign rem = use_special ? sp_r : (neg_r ? -r : r);
endmodule
