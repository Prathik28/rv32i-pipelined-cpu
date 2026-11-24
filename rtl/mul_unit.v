// Single-cycle multiplier: MUL, MULH, MULHSU, MULHU (funct3 = 0..3)
module mul_unit (
    input  [31:0] a,
    input  [31:0] b,
    input  [1:0]  op,
    output [31:0] y
);
    wire a_signed = (op != 2'b11);            // MULH, MULHSU treat a as signed
    wire b_signed = (op == 2'b01);            // MULH treats b as signed
    wire signed [32:0] ma = {a_signed & a[31], a};
    wire signed [32:0] mb = {b_signed & b[31], b};
    wire signed [65:0] p  = ma * mb;
    assign y = (op == 2'b00) ? p[31:0] : p[63:32];
endmodule
