// Main decoder (ID stage): RV32I + M + Zicsr + machine-mode system instructions.
// Unsupported / malformed encodings raise `illegal` (and have all side effects cleared).
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
    output reg        uses_rs1,
    output reg        uses_rs2,
    output reg        is_mul,
    output reg        is_div,
    output reg        is_csr,
    output reg        is_mret,
    output reg        is_ecall,
    output reg        is_ebreak,
    output reg        is_amo,        // LR / SC / AMO*  (A extension)
    output reg        is_fencei,
    output reg        illegal
);
    localparam ADD=4'd0, SUB=4'd1, SLL=4'd2, SLT=4'd3, SLTU=4'd4, XOR=4'd5,
               SRL=4'd6, SRA=4'd7, OR=4'd8, AND=4'd9, PASSB=4'd10;

    wire [6:0] opcode = instr[6:0];
    wire [2:0] f3     = instr[14:12];
    wire [6:0] f7     = instr[31:25];
    wire       f7b5   = instr[30];

    always @* begin
        reg_write = 0; mem_read = 0; mem_write = 0; alu_src_imm = 0;
        alu_src_pc = 0; alu_ctl = ADD; branch = 0; jal = 0; jalr = 0;
        uses_rs1 = 0; uses_rs2 = 0; is_mul = 0; is_div = 0; is_csr = 0;
        is_mret = 0; is_ecall = 0; is_ebreak = 0; illegal = 0;
        is_amo = 0; is_fencei = 0;

        if (instr[1:0] != 2'b11) illegal = 1;   // no compressed (C) support
        else case (opcode)
            7'b0110011: begin // R-type (+ M extension)
                reg_write = 1; uses_rs1 = 1; uses_rs2 = 1;
                if (f7 == 7'b0000001) begin
                    if (f3[2]) is_div = 1; else is_mul = 1;
                end else if (f7 == 7'b0000000 ||
                             (f7 == 7'b0100000 && (f3 == 3'b000 || f3 == 3'b101))) begin
                    case (f3)
                        3'b000: alu_ctl = f7b5 ? SUB : ADD;
                        3'b001: alu_ctl = SLL;
                        3'b010: alu_ctl = SLT;
                        3'b011: alu_ctl = SLTU;
                        3'b100: alu_ctl = XOR;
                        3'b101: alu_ctl = f7b5 ? SRA : SRL;
                        3'b110: alu_ctl = OR;
                        default: alu_ctl = AND;
                    endcase
                end else illegal = 1;
            end
            7'b0010011: begin // I-type ALU
                reg_write = 1; uses_rs1 = 1; alu_src_imm = 1;
                case (f3)
                    3'b000: alu_ctl = ADD;
                    3'b001: begin alu_ctl = SLL; if (f7 != 0) illegal = 1; end
                    3'b010: alu_ctl = SLT;
                    3'b011: alu_ctl = SLTU;
                    3'b100: alu_ctl = XOR;
                    3'b101: begin alu_ctl = f7b5 ? SRA : SRL;
                                  if (f7 != 0 && f7 != 7'b0100000) illegal = 1; end
                    3'b110: alu_ctl = OR;
                    default: alu_ctl = AND;
                endcase
            end
            7'b0000011: begin // loads
                reg_write = 1; mem_read = 1; uses_rs1 = 1; alu_src_imm = 1;
                if (!(f3 == 3'b000 || f3 == 3'b001 || f3 == 3'b010 ||
                      f3 == 3'b100 || f3 == 3'b101)) illegal = 1;
            end
            7'b0100011: begin // stores
                mem_write = 1; uses_rs1 = 1; uses_rs2 = 1; alu_src_imm = 1;
                if (f3 > 3'b010) illegal = 1;
            end
            7'b1100011: begin // branches
                branch = 1; uses_rs1 = 1; uses_rs2 = 1;
                if (f3 == 3'b010 || f3 == 3'b011) illegal = 1;
            end
            7'b1101111: begin reg_write = 1; jal = 1; end                         // JAL
            7'b1100111: begin reg_write = 1; jalr = 1; uses_rs1 = 1;              // JALR
                              alu_src_imm = 1; if (f3 != 0) illegal = 1; end
            7'b0110111: begin reg_write = 1; alu_src_imm = 1; alu_ctl = PASSB; end // LUI
            7'b0010111: begin reg_write = 1; alu_src_imm = 1; alu_src_pc = 1; end  // AUIPC
            7'b0001111: is_fencei = (f3 == 3'b001);                                // FENCE = NOP, FENCE.I
            7'b0101111: begin // A extension (word only)
                is_amo = 1; reg_write = 1; mem_read = 1; uses_rs1 = 1; alu_src_imm = 1;
                mem_write = (instr[31:27] != 5'b00010);               // everything but LR writes
                uses_rs2  = (instr[31:27] != 5'b00010);
                if (f3 != 3'b010) illegal = 1;
                case (instr[31:27])
                    5'b00010: if (instr[24:20] != 5'b0) illegal = 1;   // LR needs rs2 = 0
                    5'b00011, 5'b00001, 5'b00000, 5'b00100, 5'b01100,
                    5'b01000, 5'b10000, 5'b10100, 5'b11000, 5'b11100: ;
                    default: illegal = 1;
                endcase
            end
            7'b1110011: begin // SYSTEM
                if (f3 == 3'b000) begin
                    case (instr)
                        32'h0000_0073: is_ecall  = 1;
                        32'h0010_0073: is_ebreak = 1;
                        32'h3020_0073: is_mret   = 1;
                        32'h1050_0073: ;                 // WFI = NOP
                        default: illegal = 1;
                    endcase
                end else if (f3 == 3'b100) illegal = 1;
                else begin is_csr = 1; reg_write = 1; uses_rs1 = ~f3[2]; end
            end
            default: illegal = 1;
        endcase

        if (illegal) begin  // an illegal instruction must have no architectural side effects
            reg_write = 0; mem_read = 0; mem_write = 0; branch = 0; jal = 0; jalr = 0;
            uses_rs1 = 0; uses_rs2 = 0; is_mul = 0; is_div = 0; is_csr = 0;
            is_mret = 0; is_ecall = 0; is_ebreak = 0; is_amo = 0; is_fencei = 0;
        end
    end
endmodule
