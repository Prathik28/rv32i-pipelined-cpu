// MIPS32 main decoder (ID stage). Unknown encodings raise a Reserved Instruction exception (`ri`).
module mips_control (
    input  [31:0] instr,
    output reg        reg_write,
    output reg [1:0]  dest_sel,       // 0 = rt, 1 = rd, 2 = $31
    output reg        mem_read,
    output reg        mem_write,
    output reg [1:0]  mem_size,       // 0 byte, 1 half, 2 word
    output reg        mem_unsigned,
    output reg        mem_left,       // LWL / SWL
    output reg        mem_right,      // LWR / SWR
    output reg [3:0]  alu_op,
    output reg        alu_src_imm,
    output reg        imm_zext,
    output reg        shift_imm,
    output reg        shift_var,
    output reg        link,           // result = PC + 8 (JAL, JALR, *AL branches)
    output reg        ov_chk,         // ADD / ADDI / SUB trap on signed overflow
    output reg        is_branch,      // conditional branch (resolved in ID)
    output reg [2:0]  br_type,        // 0 beq 1 bne 2 blez 3 bgtz 4 bltz 5 bgez
    output reg        br_likely,      // branch-likely: delay slot annulled when not taken
    output reg        is_j,           // J / JAL
    output reg        is_jr,          // JR / JALR
    output reg        use_rs_ex, use_rt_ex,   // operands read in EX (forwarding / load-use)
    output reg        use_rs_id, use_rt_id,   // operands read in ID (branches, jumps)
    output reg        is_mult, is_multu, is_div, is_divu,
    output reg        is_mfhi, is_mflo, is_mthi, is_mtlo, is_mul3,
    output reg        is_syscall, is_break, is_eret, is_mfc0, is_mtc0,
    output reg        ri
);
    localparam ADD=4'd0, SUB=4'd1, AND=4'd2, OR=4'd3, XOR=4'd4, NOR=4'd5, SLT=4'd6, SLTU=4'd7,
               SLL=4'd8, SRL=4'd9, SRA=4'd10, LUI=4'd11;
    wire [5:0] op = instr[31:26];
    wire [5:0] fn = instr[5:0];
    wire [4:0] rs = instr[25:21];
    wire [4:0] rt = instr[20:16];

    task rtype(input [3:0] a); begin reg_write=1; dest_sel=1; alu_op=a; use_rs_ex=1; use_rt_ex=1; end endtask
    task itype(input [3:0] a); begin reg_write=1; alu_op=a; alu_src_imm=1; use_rs_ex=1; end endtask
    task load(input [1:0] sz, input u); begin reg_write=1; mem_read=1; mem_size=sz; mem_unsigned=u; alu_src_imm=1; use_rs_ex=1; end endtask
    task store(input [1:0] sz); begin mem_write=1; mem_size=sz; alu_src_imm=1; use_rs_ex=1; use_rt_ex=1; end endtask
    task branch2(input [2:0] t, input likely); begin is_branch=1; br_type=t; br_likely=likely; use_rs_id=1; use_rt_id=1; end endtask
    task branch1(input [2:0] t, input likely, input lnk); begin
        is_branch=1; br_type=t; br_likely=likely; use_rs_id=1;
        if (lnk) begin link=1; reg_write=1; dest_sel=2; end
    end endtask

    always @* begin
        reg_write = 0; dest_sel = 0; mem_read = 0; mem_write = 0; mem_size = 2; mem_unsigned = 0;
        mem_left = 0; mem_right = 0; alu_op = ADD; alu_src_imm = 0; imm_zext = 0; shift_imm = 0;
        shift_var = 0; link = 0; ov_chk = 0; is_branch = 0; br_type = 0; br_likely = 0; is_j = 0; is_jr = 0;
        use_rs_ex = 0; use_rt_ex = 0; use_rs_id = 0; use_rt_id = 0;
        is_mult = 0; is_multu = 0; is_div = 0; is_divu = 0;
        is_mfhi = 0; is_mflo = 0; is_mthi = 0; is_mtlo = 0; is_mul3 = 0;
        is_syscall = 0; is_break = 0; is_eret = 0; is_mfc0 = 0; is_mtc0 = 0; ri = 0;

        case (op)
            6'h00: begin // SPECIAL
                case (fn)
                    6'h00: begin reg_write=1; dest_sel=1; alu_op=SLL; shift_imm=1; use_rt_ex=1; end // sll (nop = 0)
                    6'h02: begin reg_write=1; dest_sel=1; alu_op=SRL; shift_imm=1; use_rt_ex=1; end
                    6'h03: begin reg_write=1; dest_sel=1; alu_op=SRA; shift_imm=1; use_rt_ex=1; end
                    6'h04: begin rtype(SLL); shift_var=1; end
                    6'h06: begin rtype(SRL); shift_var=1; end
                    6'h07: begin rtype(SRA); shift_var=1; end
                    6'h08: begin is_jr=1; use_rs_id=1; end                                          // jr
                    6'h09: begin is_jr=1; use_rs_id=1; reg_write=1; dest_sel=1; link=1; end         // jalr
                    6'h0C: is_syscall = 1;
                    6'h0D: is_break = 1;
                    6'h10: begin reg_write=1; dest_sel=1; is_mfhi=1; end
                    6'h11: begin is_mthi=1; use_rs_ex=1; end
                    6'h12: begin reg_write=1; dest_sel=1; is_mflo=1; end
                    6'h13: begin is_mtlo=1; use_rs_ex=1; end
                    6'h18: begin is_mult=1;  use_rs_ex=1; use_rt_ex=1; end
                    6'h19: begin is_multu=1; use_rs_ex=1; use_rt_ex=1; end
                    6'h1A: begin is_div=1;   use_rs_ex=1; use_rt_ex=1; end
                    6'h1B: begin is_divu=1;  use_rs_ex=1; use_rt_ex=1; end
                    6'h20: begin rtype(ADD); ov_chk=1; end                                           // add (traps on overflow)
                    6'h21: rtype(ADD);
                    6'h22: begin rtype(SUB); ov_chk=1; end                                           // sub (traps on overflow)
                    6'h23: rtype(SUB);
                    6'h24: rtype(AND);
                    6'h25: rtype(OR);
                    6'h26: rtype(XOR);
                    6'h27: rtype(NOR);
                    6'h2A: rtype(SLT);
                    6'h2B: rtype(SLTU);
                    default: ri = 1;
                endcase
            end
            6'h1C: if (fn == 6'h02) begin reg_write=1; dest_sel=1; is_mul3=1; use_rs_ex=1; use_rt_ex=1; end // mul rd,rs,rt
                   else ri = 1;
            6'h01: begin // REGIMM
                case (rt)
                    5'h00: branch1(4, 0, 0);   5'h01: branch1(5, 0, 0);          // bltz, bgez
                    5'h02: branch1(4, 1, 0);   5'h03: branch1(5, 1, 0);          // bltzl, bgezl
                    5'h10: branch1(4, 0, 1);   5'h11: branch1(5, 0, 1);          // bltzal, bgezal
                    5'h12: branch1(4, 1, 1);   5'h13: branch1(5, 1, 1);          // bltzall, bgezall
                    default: ri = 1;
                endcase
            end
            6'h02: is_j = 1;                                                               // j
            6'h03: begin is_j=1; link=1; reg_write=1; dest_sel=2; end                      // jal
            6'h04: branch2(0, 0);   6'h05: branch2(1, 0);                                  // beq, bne
            6'h06: branch1(2, 0, 0); 6'h07: branch1(3, 0, 0);                              // blez, bgtz
            6'h14: branch2(0, 1);   6'h15: branch2(1, 1);                                  // beql, bnel
            6'h16: branch1(2, 1, 0); 6'h17: branch1(3, 1, 0);                              // blezl, bgtzl
            6'h08: begin itype(ADD); ov_chk=1; end                                         // addi (traps)
            6'h09: itype(ADD);                                                             // addiu
            6'h0A: itype(SLT);
            6'h0B: itype(SLTU);
            6'h0C: begin itype(AND); imm_zext=1; end
            6'h0D: begin itype(OR);  imm_zext=1; end
            6'h0E: begin itype(XOR); imm_zext=1; end
            6'h0F: begin reg_write=1; alu_op=LUI; alu_src_imm=1; imm_zext=1; end
            6'h10: begin // COP0
                if (rs == 5'h00 && instr[10:3] == 8'b0)        begin is_mfc0 = 1; reg_write = 1; end
                else if (rs == 5'h04 && instr[10:3] == 8'b0)   begin is_mtc0 = 1; use_rt_ex = 1; end
                else if (rs == 5'h10 && fn == 6'h18)           is_eret = 1;
                else ri = 1;
            end
            6'h20: load(0, 0);   6'h21: load(1, 0);   6'h23: load(2, 0);                    // lb lh lw
            6'h24: load(0, 1);   6'h25: load(1, 1);                                         // lbu lhu
            6'h22: begin load(2, 0); mem_left = 1;  use_rt_ex = 1; end                      // lwl (merges with rt)
            6'h26: begin load(2, 0); mem_right = 1; use_rt_ex = 1; end                      // lwr
            6'h28: store(0);     6'h29: store(1);     6'h2B: store(2);                      // sb sh sw
            6'h2A: begin store(2); mem_left = 1;  end                                       // swl
            6'h2E: begin store(2); mem_right = 1; end                                       // swr
            default: ri = 1;
        endcase
    end
endmodule
