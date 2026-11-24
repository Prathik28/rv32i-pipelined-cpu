// MIPS32 main decoder (ID stage). Unknown encodings behave as NOPs.
module mips_control (
    input  [31:0] instr,
    output reg        reg_write,
    output reg [1:0]  dest_sel,       // 0 = rt, 1 = rd, 2 = $31
    output reg        mem_read,
    output reg        mem_write,
    output reg [1:0]  mem_size,       // 0 byte, 1 half, 2 word
    output reg        mem_unsigned,
    output reg [3:0]  alu_op,
    output reg        alu_src_imm,
    output reg        imm_zext,
    output reg        shift_imm,
    output reg        shift_var,
    output reg        link,           // result = PC + 8 (JAL, JALR, BLTZAL, BGEZAL)
    output reg        is_branch,      // conditional branch (resolved in ID)
    output reg [2:0]  br_type,        // 0 beq 1 bne 2 blez 3 bgtz 4 bltz 5 bgez
    output reg        is_j,           // J / JAL
    output reg        is_jr,          // JR / JALR
    output reg        use_rs_ex, use_rt_ex,   // operands read in EX (forwarding / load-use)
    output reg        use_rs_id, use_rt_id,   // operands read in ID (branches, jumps)
    output reg        is_mult, is_multu, is_div, is_divu,
    output reg        is_mfhi, is_mflo, is_mthi, is_mtlo, is_mul3,
    output reg        is_syscall
);
    localparam ADD=4'd0, SUB=4'd1, AND=4'd2, OR=4'd3, XOR=4'd4, NOR=4'd5, SLT=4'd6, SLTU=4'd7,
               SLL=4'd8, SRL=4'd9, SRA=4'd10, LUI=4'd11;
    wire [5:0] op = instr[31:26];
    wire [5:0] fn = instr[5:0];
    wire [4:0] rt = instr[20:16];

    always @* begin
        reg_write = 0; dest_sel = 0; mem_read = 0; mem_write = 0; mem_size = 2; mem_unsigned = 0;
        alu_op = ADD; alu_src_imm = 0; imm_zext = 0; shift_imm = 0; shift_var = 0; link = 0;
        is_branch = 0; br_type = 0; is_j = 0; is_jr = 0;
        use_rs_ex = 0; use_rt_ex = 0; use_rs_id = 0; use_rt_id = 0;
        is_mult = 0; is_multu = 0; is_div = 0; is_divu = 0;
        is_mfhi = 0; is_mflo = 0; is_mthi = 0; is_mtlo = 0; is_mul3 = 0; is_syscall = 0;

        case (op)
            6'h00: begin // SPECIAL
                case (fn)
                    6'h00: begin reg_write=1; dest_sel=1; alu_op=SLL; shift_imm=1; use_rt_ex=1; end // sll (nop = 0)
                    6'h02: begin reg_write=1; dest_sel=1; alu_op=SRL; shift_imm=1; use_rt_ex=1; end
                    6'h03: begin reg_write=1; dest_sel=1; alu_op=SRA; shift_imm=1; use_rt_ex=1; end
                    6'h04: begin reg_write=1; dest_sel=1; alu_op=SLL; shift_var=1; use_rs_ex=1; use_rt_ex=1; end
                    6'h06: begin reg_write=1; dest_sel=1; alu_op=SRL; shift_var=1; use_rs_ex=1; use_rt_ex=1; end
                    6'h07: begin reg_write=1; dest_sel=1; alu_op=SRA; shift_var=1; use_rs_ex=1; use_rt_ex=1; end
                    6'h08: begin is_jr=1; use_rs_id=1; end                                          // jr
                    6'h09: begin is_jr=1; use_rs_id=1; reg_write=1; dest_sel=1; link=1; end         // jalr
                    6'h0C: begin is_syscall=1; use_rs_ex=1; end                                     // syscall ($a0 = exit code)
                    6'h10: begin reg_write=1; dest_sel=1; is_mfhi=1; end
                    6'h11: begin is_mthi=1; use_rs_ex=1; end
                    6'h12: begin reg_write=1; dest_sel=1; is_mflo=1; end
                    6'h13: begin is_mtlo=1; use_rs_ex=1; end
                    6'h18: begin is_mult=1;  use_rs_ex=1; use_rt_ex=1; end
                    6'h19: begin is_multu=1; use_rs_ex=1; use_rt_ex=1; end
                    6'h1A: begin is_div=1;   use_rs_ex=1; use_rt_ex=1; end
                    6'h1B: begin is_divu=1;  use_rs_ex=1; use_rt_ex=1; end
                    6'h20, 6'h21: begin reg_write=1; dest_sel=1; alu_op=ADD;  use_rs_ex=1; use_rt_ex=1; end // add/addu (no overflow trap)
                    6'h22, 6'h23: begin reg_write=1; dest_sel=1; alu_op=SUB;  use_rs_ex=1; use_rt_ex=1; end // sub/subu
                    6'h24: begin reg_write=1; dest_sel=1; alu_op=AND;  use_rs_ex=1; use_rt_ex=1; end
                    6'h25: begin reg_write=1; dest_sel=1; alu_op=OR;   use_rs_ex=1; use_rt_ex=1; end
                    6'h26: begin reg_write=1; dest_sel=1; alu_op=XOR;  use_rs_ex=1; use_rt_ex=1; end
                    6'h27: begin reg_write=1; dest_sel=1; alu_op=NOR;  use_rs_ex=1; use_rt_ex=1; end
                    6'h2A: begin reg_write=1; dest_sel=1; alu_op=SLT;  use_rs_ex=1; use_rt_ex=1; end
                    6'h2B: begin reg_write=1; dest_sel=1; alu_op=SLTU; use_rs_ex=1; use_rt_ex=1; end
                    default: ;
                endcase
            end
            6'h1C: if (fn == 6'h02) begin reg_write=1; dest_sel=1; is_mul3=1; use_rs_ex=1; use_rt_ex=1; end // mul rd,rs,rt
            6'h01: begin // REGIMM
                is_branch=1; use_rs_id=1;
                case (rt)
                    5'h00: br_type = 4;                                    // bltz
                    5'h01: br_type = 5;                                    // bgez
                    5'h10: begin br_type = 4; link=1; reg_write=1; dest_sel=2; end  // bltzal
                    5'h11: begin br_type = 5; link=1; reg_write=1; dest_sel=2; end  // bgezal
                    default: is_branch = 0;
                endcase
            end
            6'h02: is_j = 1;                                                               // j
            6'h03: begin is_j=1; link=1; reg_write=1; dest_sel=2; end                      // jal
            6'h04: begin is_branch=1; br_type=0; use_rs_id=1; use_rt_id=1; end             // beq
            6'h05: begin is_branch=1; br_type=1; use_rs_id=1; use_rt_id=1; end             // bne
            6'h06: begin is_branch=1; br_type=2; use_rs_id=1; end                          // blez
            6'h07: begin is_branch=1; br_type=3; use_rs_id=1; end                          // bgtz
            6'h08, 6'h09: begin reg_write=1; alu_op=ADD;  alu_src_imm=1; use_rs_ex=1; end  // addi/addiu
            6'h0A: begin reg_write=1; alu_op=SLT;  alu_src_imm=1; use_rs_ex=1; end
            6'h0B: begin reg_write=1; alu_op=SLTU; alu_src_imm=1; use_rs_ex=1; end
            6'h0C: begin reg_write=1; alu_op=AND;  alu_src_imm=1; imm_zext=1; use_rs_ex=1; end
            6'h0D: begin reg_write=1; alu_op=OR;   alu_src_imm=1; imm_zext=1; use_rs_ex=1; end
            6'h0E: begin reg_write=1; alu_op=XOR;  alu_src_imm=1; imm_zext=1; use_rs_ex=1; end
            6'h0F: begin reg_write=1; alu_op=LUI;  alu_src_imm=1; imm_zext=1; end
            6'h20: begin reg_write=1; mem_read=1; mem_size=0; alu_src_imm=1; use_rs_ex=1; end               // lb
            6'h21: begin reg_write=1; mem_read=1; mem_size=1; alu_src_imm=1; use_rs_ex=1; end               // lh
            6'h23: begin reg_write=1; mem_read=1; mem_size=2; alu_src_imm=1; use_rs_ex=1; end               // lw
            6'h24: begin reg_write=1; mem_read=1; mem_size=0; mem_unsigned=1; alu_src_imm=1; use_rs_ex=1; end // lbu
            6'h25: begin reg_write=1; mem_read=1; mem_size=1; mem_unsigned=1; alu_src_imm=1; use_rs_ex=1; end // lhu
            6'h28: begin mem_write=1; mem_size=0; alu_src_imm=1; use_rs_ex=1; use_rt_ex=1; end               // sb
            6'h29: begin mem_write=1; mem_size=1; alu_src_imm=1; use_rs_ex=1; use_rt_ex=1; end               // sh
            6'h2B: begin mem_write=1; mem_size=2; alu_src_imm=1; use_rs_ex=1; use_rt_ex=1; end               // sw
            default: ;
        endcase
    end
endmodule
