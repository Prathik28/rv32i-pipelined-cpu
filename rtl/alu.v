// ALU for RV32I
module alu (
    input  [31:0] a,
    input  [31:0] b,
    input  [3:0]  ctl,
    output reg [31:0] y
);
    localparam ADD=4'd0, SUB=4'd1, SLL=4'd2, SLT=4'd3, SLTU=4'd4, XOR=4'd5,
               SRL=4'd6, SRA=4'd7, OR=4'd8, AND=4'd9, PASSB=4'd10;
    always @* begin
        case (ctl)
            ADD:   y = a + b;
            SUB:   y = a - b;
            SLL:   y = a << b[4:0];
            SLT:   y = {31'b0, $signed(a) < $signed(b)};
            SLTU:  y = {31'b0, a < b};
            XOR:   y = a ^ b;
            SRL:   y = a >> b[4:0];
            SRA:   y = $signed(a) >>> b[4:0];
            OR:    y = a | b;
            AND:   y = a & b;
            PASSB: y = b;
            default: y = 32'b0;
        endcase
    end
endmodule
