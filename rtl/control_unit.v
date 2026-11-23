// Main decoder (ID stage)
module control_unit (
    input  [31:0] instr,
    output reg        reg_write,
    output reg        mem_read,
    output reg        mem_write,
    output reg        alu_src_imm,   // ALU B operand = imm
    output reg        alu_src_pc,    // ALU A operand = pc (AUIPC)
    output reg [3:0]  alu_ctl,
    output reg        branch,
    output reg        jal,
    output reg        jalr,
    output reg        system,        // ECALL / EBREAK -> halt
    output reg        uses_rs1,
    output reg        uses_rs2
);
    localparam ADD=4'd0, SUB=4'd1, SLL=4'd2, SLT=4'd3, SLTU=4'd4, XOR=4'd5,
               SRL=4'd6, SRA=4'd7, OR=4'd8, AND=4'd9, PASSB=4'd10;

    wire [6:0] opcode = instr[6:0];
    wire [2:0] f3     = instr[14:12];
    wire       f7b5   = instr[30];

    always @* begin
        reg_write = 0; mem_read = 0; mem_write = 0; alu_src_imm = 0;
        alu_src_pc = 0; alu_ctl = ADD; branch = 0; jal = 0; jalr = 0;
        system = 0; uses_rs1 = 0; uses_rs2 = 0;

        case (opcode)
            7'b0110011: begin // R-type
                reg_write = 1; uses_rs1 = 1; uses_rs2 = 1;
                case (f3)
                    3'b000: alu_ctl = f7b5 ? SUB : ADD;
                    3'b001: alu_ctl = SLL;
                    3'b010: alu_ctl = SLT;
                    3'b011: alu_ctl = SLTU;
                    3'b100: alu_ctl = XOR;
                    3'b101: alu_ctl = f7b5 ? SRA : SRL;
                    3'b110: alu_ctl = OR;
                    3'b111: alu_ctl = AND;
                endcase
            end
            7'b0010011: begin // I-type ALU
                reg_write = 1; uses_rs1 = 1; alu_src_imm = 1;
                case (f3)
                    3'b000: alu_ctl = ADD;
                    3'b001: alu_ctl = SLL;
                    3'b010: alu_ctl = SLT;
                    3'b011: alu_ctl = SLTU;
                    3'b100: alu_ctl = XOR;
                    3'b101: alu_ctl = f7b5 ? SRA : SRL;
                    3'b110: alu_ctl = OR;
                    3'b111: alu_ctl = AND;
                endcase
            end
            7'b0000011: begin // loads
                reg_write = 1; mem_read = 1; uses_rs1 = 1; alu_src_imm = 1;
            end
            7'b0100011: begin // stores
                mem_write = 1; uses_rs1 = 1; uses_rs2 = 1; alu_src_imm = 1;
            end
            7'b1100011: begin // branches
                branch = 1; uses_rs1 = 1; uses_rs2 = 1;
            end
            7'b1101111: begin // JAL
                reg_write = 1; jal = 1;
            end
            7'b1100111: begin // JALR
                reg_write = 1; jalr = 1; uses_rs1 = 1; alu_src_imm = 1;
            end
            7'b0110111: begin // LUI
                reg_write = 1; alu_src_imm = 1; alu_ctl = PASSB;
            end
            7'b0010111: begin // AUIPC
                reg_write = 1; alu_src_imm = 1; alu_src_pc = 1;
            end
            7'b1110011: system = 1; // ECALL / EBREAK
            default: ; // FENCE and unknown -> NOP
        endcase
    end
endmodule
