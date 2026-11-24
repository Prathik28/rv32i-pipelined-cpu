// =============================================================================
// 5-stage pipelined MIPS32 core:  IF -> ID -> EX -> MEM -> WB
//
// Branch delay slot: the instruction after every branch/jump ALWAYS executes (except after a
// not-taken branch-LIKELY, which annuls it). Branches and jumps resolve in ID, so the delay slot
// hides the branch penalty - no flush, no prediction.
//
// Hazard handling
//   Data (RAW)    : EX/MEM->EX and MEM/WB->EX forwarding; WB->ID regfile write-through;
//                   load-use: 1-cycle stall (loads return data from MEM).
//   Control       : branch/jump operands are needed in ID:
//                     ALU producer in MEM  -> forwarded into the ID comparator
//                     producer in EX       -> 1 stall
//                     LOAD in MEM          -> 1 more stall (2 in total for load -> branch)
//   Structural    : Harvard memories; regfile write-through; iterative divider stalls the front end;
//                   HI/LO are written and read in EX (in program order).
//   Exceptions    : precise, taken in EX (the faulting instruction never commits; younger ones are
//                   flushed): overflow, address error (load/store), syscall, break, reserved
//                   instruction, and interrupts (2 software + timer). EPC/BD follow the delay-slot
//                   rules (an exception in a delay slot reports the BRANCH in EPC with BD = 1).
//                   ERET returns without a delay slot. Vector: 0x180.
// =============================================================================
module mips_core (
    input         clk,
    input         rst,
    output [31:0] imem_addr,
    input  [31:0] imem_rdata,
    output        dmem_we,
    output [31:0] dmem_addr,
    output [31:0] dmem_wdata,
    output [3:0]  dmem_be,
    input  [31:0] dmem_rdata,
    input         stop,
    output reg [31:0] perf_cycles,
    output reg [31:0] perf_instret,
    output reg [31:0] perf_stall_lu,    // load-use stall cycles
    output reg [31:0] perf_stall_br,    // branch-operand stall cycles
    output reg [31:0] perf_stall_div,   // divider busy cycles
    output reg [31:0] perf_taken,       // taken branches / jumps
    output reg [31:0] perf_traps        // exceptions + interrupts
);
    localparam NOP = 32'h0000_0000;
    localparam VECTOR = 32'h0000_0180;

    wire stall_lu, stall_br, ex_stall;
    wire stall_front = stall_lu | stall_br | ex_stall;
    wire        id_redirect;
    wire [31:0] id_target;
    wire        flush;                  // exception / ERET redirect from EX
    wire [31:0] flush_pc;

    // ============================================================ IF
    reg [31:0] pc;
    assign imem_addr = pc;
    always @(posedge clk) begin
        if (rst)                pc <= 32'b0;
        else if (flush)         pc <= flush_pc;
        else if (!stall_front)  pc <= id_redirect ? id_target : pc + 32'd4;
    end

    reg [31:0] ifid_pc, ifid_instr;
    reg        ifid_valid;
    wire       annul;                   // not-taken branch-likely: kill the delay slot being fetched
    always @(posedge clk) begin
        if (rst || flush) begin ifid_pc <= 0; ifid_instr <= NOP; ifid_valid <= 0; end
        else if (!stall_front) begin
            ifid_pc <= pc; ifid_instr <= annul ? NOP : imem_rdata; ifid_valid <= ~annul;
        end
    end

    // ============================================================ ID
    wire [4:0]  rs_f = ifid_instr[25:21], rt_f = ifid_instr[20:16], rd_f = ifid_instr[15:11];
    wire [15:0] imm16 = ifid_instr[15:0];

    wire c_reg_write, c_mem_read, c_mem_write, c_mem_unsigned, c_mem_left, c_mem_right;
    wire c_alu_src_imm, c_imm_zext, c_shift_imm, c_shift_var, c_link, c_ov, c_is_branch, c_likely;
    wire c_is_j, c_is_jr, c_use_rs_ex, c_use_rt_ex, c_use_rs_id, c_use_rt_id;
    wire c_mult, c_multu, c_div, c_divu, c_mfhi, c_mflo, c_mthi, c_mtlo, c_mul3;
    wire c_syscall, c_break, c_eret, c_mfc0, c_mtc0, c_ri;
    wire [1:0] c_dest_sel, c_mem_size;
    wire [3:0] c_alu_op;
    wire [2:0] c_br_type;

    mips_control u_ctl (
        .instr(ifid_instr),
        .reg_write(c_reg_write), .dest_sel(c_dest_sel), .mem_read(c_mem_read), .mem_write(c_mem_write),
        .mem_size(c_mem_size), .mem_unsigned(c_mem_unsigned), .mem_left(c_mem_left), .mem_right(c_mem_right),
        .alu_op(c_alu_op), .alu_src_imm(c_alu_src_imm), .imm_zext(c_imm_zext), .shift_imm(c_shift_imm),
        .shift_var(c_shift_var), .link(c_link), .ov_chk(c_ov), .is_branch(c_is_branch), .br_type(c_br_type),
        .br_likely(c_likely), .is_j(c_is_j), .is_jr(c_is_jr),
        .use_rs_ex(c_use_rs_ex), .use_rt_ex(c_use_rt_ex), .use_rs_id(c_use_rs_id), .use_rt_id(c_use_rt_id),
        .is_mult(c_mult), .is_multu(c_multu), .is_div(c_div), .is_divu(c_divu),
        .is_mfhi(c_mfhi), .is_mflo(c_mflo), .is_mthi(c_mthi), .is_mtlo(c_mtlo), .is_mul3(c_mul3),
        .is_syscall(c_syscall), .is_break(c_break), .is_eret(c_eret), .is_mfc0(c_mfc0), .is_mtc0(c_mtc0),
        .ri(c_ri)
    );

    wire [4:0] id_dest = (c_dest_sel == 2'd0) ? rt_f : (c_dest_sel == 2'd1) ? rd_f : 5'd31;

    wire [31:0] rf_a, rf_b;
    wire        wb_reg_write;
    wire [4:0]  wb_dest;
    wire [31:0] wb_data;
    regfile rf (.clk(clk), .we(wb_reg_write), .waddr(wb_dest), .wdata(wb_data),
                .raddr1(rs_f), .raddr2(rt_f), .rdata1(rf_a), .rdata2(rf_b));

    reg [4:0]  idex_dest;
    reg        idex_reg_write, idex_mem_read;
    reg [31:0] exmem_result;
    reg [4:0]  exmem_dest;
    reg        exmem_reg_write, exmem_mem_read;

    // ---- branch / jump resolution in ID (operands forwarded from an ALU result in MEM) ----
    wire fwd_a_id = exmem_reg_write && !exmem_mem_read && exmem_dest != 0 && exmem_dest == rs_f;
    wire fwd_b_id = exmem_reg_write && !exmem_mem_read && exmem_dest != 0 && exmem_dest == rt_f;
    wire [31:0] id_a = fwd_a_id ? exmem_result : rf_a;
    wire [31:0] id_b = fwd_b_id ? exmem_result : rf_b;

    wire eq  = (id_a == id_b);
    wire ltz = id_a[31];
    wire lez = id_a[31] | (id_a == 32'b0);
    reg  taken;
    always @* begin
        case (c_br_type)
            3'd0: taken = eq;     3'd1: taken = ~eq;
            3'd2: taken = lez;    3'd3: taken = ~lez;
            3'd4: taken = ltz;    default: taken = ~ltz;
        endcase
    end
    wire [31:0] pc4      = ifid_pc + 32'd4;
    wire [31:0] br_tgt   = pc4 + {{14{imm16[15]}}, imm16, 2'b00};
    wire [31:0] j_tgt    = {pc4[31:28], ifid_instr[25:0], 2'b00};
    assign id_target     = c_is_j ? j_tgt : c_is_jr ? id_a : br_tgt;
    assign id_redirect   = ifid_valid & ~stall_front & ~flush & (c_is_j | c_is_jr | (c_is_branch & taken));
    assign annul         = ifid_valid & ~stall_front & c_is_branch & c_likely & ~taken;

    // delay-slot tracking: the instruction that follows a branch/jump (in program order) is in its delay slot
    reg prev_ctrl;
    always @(posedge clk) begin
        if (rst || flush) prev_ctrl <= 1'b0;
        else if (!stall_front) prev_ctrl <= ifid_valid & (c_is_branch | c_is_j | c_is_jr);
    end

    // ---- stalls ----
    wire br_dep_ex  = idex_reg_write && idex_dest != 0 &&
                      ((c_use_rs_id && idex_dest == rs_f) || (c_use_rt_id && idex_dest == rt_f));
    wire br_dep_mem = exmem_mem_read && exmem_dest != 0 &&
                      ((c_use_rs_id && exmem_dest == rs_f) || (c_use_rt_id && exmem_dest == rt_f));
    assign stall_br = ifid_valid & (br_dep_ex | br_dep_mem);
    assign stall_lu = ifid_valid & idex_mem_read && idex_dest != 0 &&
                      ((c_use_rs_ex && idex_dest == rs_f) || (c_use_rt_ex && idex_dest == rt_f));

    // ---------------------------------------------------------- ID/EX reg
    reg [31:0] idex_pc, idex_rsv, idex_rtv, idex_imm;
    reg [4:0]  idex_rs, idex_rt, idex_shamt, idex_cp0sel;
    reg [3:0]  idex_alu_op;
    reg [1:0]  idex_mem_size;
    reg        idex_mem_write, idex_mem_unsigned, idex_mem_left, idex_mem_right, idex_alu_src_imm,
               idex_shift_imm, idex_shift_var, idex_link, idex_valid, idex_mult, idex_multu, idex_div,
               idex_divu, idex_mfhi, idex_mflo, idex_mthi, idex_mtlo, idex_mul3, idex_syscall, idex_break,
               idex_eret, idex_mfc0, idex_mtc0, idex_ri, idex_ov, idex_bd;

    always @(posedge clk) begin
        if (rst || flush || (!ex_stall && (stall_lu || stall_br))) begin
            idex_reg_write <= 0; idex_mem_read <= 0; idex_mem_write <= 0; idex_dest <= 0;
            idex_rs <= 0; idex_rt <= 0; idex_valid <= 0; idex_link <= 0;
            idex_mult <= 0; idex_multu <= 0; idex_div <= 0; idex_divu <= 0; idex_mfhi <= 0;
            idex_mflo <= 0; idex_mthi <= 0; idex_mtlo <= 0; idex_mul3 <= 0; idex_syscall <= 0;
            idex_break <= 0; idex_eret <= 0; idex_mfc0 <= 0; idex_mtc0 <= 0; idex_ri <= 0; idex_ov <= 0;
            idex_bd <= 0; idex_mem_left <= 0; idex_mem_right <= 0;
            idex_alu_op <= 0; idex_alu_src_imm <= 0; idex_shift_imm <= 0; idex_shift_var <= 0;
            idex_mem_size <= 0; idex_mem_unsigned <= 0; idex_pc <= 0; idex_rsv <= 0; idex_rtv <= 0;
            idex_imm <= 0; idex_shamt <= 0; idex_cp0sel <= 0;
        end else if (!ex_stall) begin
            idex_reg_write   <= c_reg_write & ifid_valid;
            idex_mem_read    <= c_mem_read  & ifid_valid;
            idex_mem_write   <= c_mem_write & ifid_valid;
            idex_dest        <= id_dest;
            idex_rs          <= c_use_rs_ex ? rs_f : 5'd0;
            idex_rt          <= c_use_rt_ex ? rt_f : 5'd0;
            idex_valid       <= ifid_valid;
            idex_link        <= c_link & ifid_valid;
            idex_mult        <= c_mult  & ifid_valid;   idex_multu <= c_multu & ifid_valid;
            idex_div         <= c_div   & ifid_valid;   idex_divu  <= c_divu  & ifid_valid;
            idex_mfhi        <= c_mfhi  & ifid_valid;   idex_mflo  <= c_mflo  & ifid_valid;
            idex_mthi        <= c_mthi  & ifid_valid;   idex_mtlo  <= c_mtlo  & ifid_valid;
            idex_mul3        <= c_mul3  & ifid_valid;
            idex_syscall     <= c_syscall & ifid_valid; idex_break <= c_break & ifid_valid;
            idex_eret        <= c_eret & ifid_valid;
            idex_mfc0        <= c_mfc0 & ifid_valid;    idex_mtc0 <= c_mtc0 & ifid_valid;
            idex_ri          <= c_ri & ifid_valid;      idex_ov <= c_ov & ifid_valid;
            idex_bd          <= prev_ctrl;
            idex_mem_left    <= c_mem_left; idex_mem_right <= c_mem_right;
            idex_alu_op      <= c_alu_op;
            idex_alu_src_imm <= c_alu_src_imm;
            idex_shift_imm   <= c_shift_imm;  idex_shift_var <= c_shift_var;
            idex_mem_size    <= c_mem_size;   idex_mem_unsigned <= c_mem_unsigned;
            idex_pc          <= ifid_pc;
            idex_rsv         <= rf_a;  idex_rtv <= rf_b;
            idex_imm         <= c_imm_zext ? {16'b0, imm16} : {{16{imm16[15]}}, imm16};
            idex_shamt       <= ifid_instr[10:6];
            idex_cp0sel      <= rd_f;
        end
    end

    // ============================================================ EX
    reg [31:0] exmem_store;
    reg [1:0]  exmem_mem_size;
    reg        exmem_mem_write, exmem_mem_unsigned, exmem_mem_left, exmem_mem_right, exmem_valid;
    reg [4:0]  memwb_dest;
    reg        memwb_reg_write, memwb_valid;
    wire [1:0] fwd_a, fwd_b;

    mips_fwd u_fwd (.idex_rs(idex_rs), .idex_rt(idex_rt),
                    .exmem_dest(exmem_dest), .memwb_dest(memwb_dest),
                    .exmem_reg_write(exmem_reg_write), .memwb_reg_write(memwb_reg_write),
                    .fwd_a(fwd_a), .fwd_b(fwd_b));

    wire [31:0] rs_v = (fwd_a == 2'b10) ? exmem_result : (fwd_a == 2'b01) ? wb_data : idex_rsv;
    wire [31:0] rt_v = (fwd_b == 2'b10) ? exmem_result : (fwd_b == 2'b01) ? wb_data : idex_rtv;

    wire [31:0] alu_a = (idex_shift_imm | idex_shift_var) ? rt_v : rs_v;
    wire [31:0] alu_b = idex_shift_imm ? {27'b0, idex_shamt} :
                        idex_shift_var ? {27'b0, rs_v[4:0]} :
                        idex_alu_src_imm ? idex_imm : rt_v;
    wire [31:0] alu_y;
    mips_alu u_alu (.a(alu_a), .b(alu_b), .op(idex_alu_op), .y(alu_y));

    // ---- exceptions / interrupts ----
    wire add_ov = (alu_a[31] == alu_b[31]) & (alu_y[31] != alu_a[31]);
    wire sub_ov = (alu_a[31] != alu_b[31]) & (alu_y[31] != alu_a[31]);
    wire exc_ov = idex_ov & ((idex_alu_op == 4'd1) ? sub_ov : add_ov);
    wire mem_op = idex_mem_read | idex_mem_write;
    wire unal   = idex_mem_left | idex_mem_right;
    wire misal  = mem_op & ~unal & (((idex_mem_size == 2'd1) & alu_y[0]) | ((idex_mem_size == 2'd2) & (|alu_y[1:0])));
    wire exc_adel = misal & idex_mem_read;
    wire exc_ades = misal & idex_mem_write;
    wire exc_any  = idex_ri | idex_syscall | idex_break | exc_ov | exc_adel | exc_ades;

    wire        irq_pending, div_active, div_done;
    wire [31:0] cp0_rdata, epc;
    wire        irq_take  = idex_valid & irq_pending & ~div_active;
    wire        trap_take = irq_take | exc_any;
    wire        ex_commit = ~ex_stall & ~trap_take;
    wire        eret_take = idex_eret & ex_commit;

    reg [4:0] exc_code;
    always @* begin
        if (irq_take)         exc_code = 5'd0;
        else if (idex_ri)     exc_code = 5'd10;
        else if (idex_syscall) exc_code = 5'd8;
        else if (idex_break)  exc_code = 5'd9;
        else if (exc_ov)      exc_code = 5'd12;
        else if (exc_adel)    exc_code = 5'd4;
        else                  exc_code = 5'd5;
    end

    mips_cp0 u_cp0 (
        .clk(clk), .rst(rst), .reg_sel(idex_cp0sel), .write_en(idex_mtc0 & ex_commit), .wdata(rt_v),
        .rdata(cp0_rdata),
        .exc_enter(trap_take), .exc_epc(idex_bd ? idex_pc - 32'd4 : idex_pc), .exc_bd(idex_bd),
        .exc_code(exc_code), .badv_we(~irq_take & (exc_adel | exc_ades)), .badv_val(alu_y),
        .eret_commit(eret_take), .epc_o(epc), .irq_pending(irq_pending)
    );

    assign flush    = trap_take | eret_take;
    assign flush_pc = trap_take ? VECTOR : epc;

    // ---- multiply / divide, HI / LO ----
    reg [31:0] hi, lo;
    wire [63:0] prod_s = $signed(rs_v) * $signed(rt_v);
    wire [63:0] prod_u = rs_v * rt_v;
    wire [31:0] div_q, div_r;
    wire        div_any   = idex_div | idex_divu;
    wire        div_start = div_any & ~div_active & ~div_done & ~trap_take;
    mips_div u_div (.clk(clk), .rst(rst), .start(div_start), .a(rs_v), .b(rt_v), .is_signed(idex_div),
                    .active(div_active), .done(div_done), .quo(div_q), .rem(div_r));
    assign ex_stall = div_any & ~div_done & ~trap_take;

    always @(posedge clk) begin
        if (rst) begin hi <= 0; lo <= 0; end
        else if (ex_commit) begin
            if (idex_mult)       {hi, lo} <= prod_s;
            else if (idex_multu) {hi, lo} <= prod_u;
            else if (div_any)    begin hi <= div_r; lo <= div_q; end
            else if (idex_mthi)  hi <= rs_v;
            else if (idex_mtlo)  lo <= rs_v;
        end
    end

    wire [31:0] ex_result = idex_link ? (idex_pc + 32'd8) :
                            idex_mfhi ? hi : idex_mflo ? lo :
                            idex_mfc0 ? cp0_rdata :
                            idex_mul3 ? prod_s[31:0] : alu_y;

    // --------------------------------------------------------- EX/MEM reg
    always @(posedge clk) begin
        if (rst || ex_stall || trap_take) begin
            exmem_result <= 0; exmem_store <= 0; exmem_dest <= 0; exmem_reg_write <= 0;
            exmem_mem_read <= 0; exmem_mem_write <= 0; exmem_mem_size <= 0; exmem_mem_unsigned <= 0;
            exmem_mem_left <= 0; exmem_mem_right <= 0; exmem_valid <= 0;
        end else begin
            exmem_result <= ex_result;   exmem_store <= rt_v;
            exmem_dest   <= idex_dest;   exmem_reg_write <= idex_reg_write;
            exmem_mem_read <= idex_mem_read; exmem_mem_write <= idex_mem_write;
            exmem_mem_size <= idex_mem_size; exmem_mem_unsigned <= idex_mem_unsigned;
            exmem_mem_left <= idex_mem_left; exmem_mem_right <= idex_mem_right;
            exmem_valid <= idex_valid;
        end
    end

    // ============================================================ MEM
    wire [1:0] off  = exmem_result[1:0];
    wire [1:0] noff = ~off;                         // 3 - off
    assign dmem_addr = exmem_result;
    assign dmem_we   = exmem_mem_write;
    reg [3:0]  be;
    reg [31:0] wdata;
    always @* begin
        if (exmem_mem_left) begin                    // SWL: top (off+1) bytes of rt -> bytes 0..off
            be = 4'b1111 >> noff;  wdata = exmem_store >> {noff, 3'b000};
        end else if (exmem_mem_right) begin          // SWR: low (4-off) bytes of rt -> bytes off..3
            be = 4'b1111 << off;   wdata = exmem_store << {off, 3'b000};
        end else case (exmem_mem_size)
            2'd0:    begin be = 4'b0001 << off;             wdata = {4{exmem_store[7:0]}};   end
            2'd1:    begin be = off[1] ? 4'b1100 : 4'b0011; wdata = {2{exmem_store[15:0]}};  end
            default: begin be = 4'b1111;                    wdata = exmem_store;             end
        endcase
    end
    assign dmem_be = be; assign dmem_wdata = wdata;

    wire [31:0] shifted  = dmem_rdata >> {off, 3'b000};
    wire [31:0] mask_hi  = 32'hFFFF_FFFF << {noff, 3'b000};
    wire [31:0] mask_lo  = 32'hFFFF_FFFF >> {off, 3'b000};
    reg  [31:0] load_data;
    always @* begin
        if (exmem_mem_left)       // LWL: bytes 0..off of the word -> top (off+1) bytes of rt, rest of rt kept
            load_data = (exmem_store & ~mask_hi) | ((dmem_rdata << {noff, 3'b000}) & mask_hi);
        else if (exmem_mem_right) // LWR: bytes off..3 -> low (4-off) bytes of rt, rest of rt kept
            load_data = (exmem_store & ~mask_lo) | (shifted & mask_lo);
        else case (exmem_mem_size)
            2'd0:    load_data = exmem_mem_unsigned ? {24'b0, shifted[7:0]}  : {{24{shifted[7]}},  shifted[7:0]};
            2'd1:    load_data = exmem_mem_unsigned ? {16'b0, shifted[15:0]} : {{16{shifted[15]}}, shifted[15:0]};
            default: load_data = dmem_rdata;
        endcase
    end

    reg [31:0] memwb_result, memwb_load;
    reg        memwb_mem_to_reg;
    always @(posedge clk) begin
        if (rst) begin
            memwb_result <= 0; memwb_load <= 0; memwb_dest <= 0; memwb_reg_write <= 0;
            memwb_mem_to_reg <= 0; memwb_valid <= 0;
        end else begin
            memwb_result <= exmem_result; memwb_load <= load_data; memwb_dest <= exmem_dest;
            memwb_reg_write <= exmem_reg_write; memwb_mem_to_reg <= exmem_mem_read; memwb_valid <= exmem_valid;
        end
    end

    // ============================================================ WB
    assign wb_data      = memwb_mem_to_reg ? memwb_load : memwb_result;
    assign wb_dest      = memwb_dest;
    assign wb_reg_write = memwb_reg_write;

    // ---------------------------------------------------- performance counters
    always @(posedge clk) begin
        if (rst) begin
            perf_cycles <= 0; perf_instret <= 0; perf_stall_lu <= 0; perf_stall_br <= 0;
            perf_stall_div <= 0; perf_taken <= 0; perf_traps <= 0;
        end else if (!stop) begin
            perf_cycles <= perf_cycles + 1;
            if (memwb_valid)                 perf_instret   <= perf_instret + 1;
            if (stall_lu && !ex_stall)       perf_stall_lu  <= perf_stall_lu + 1;
            if (stall_br && !stall_lu && !ex_stall) perf_stall_br <= perf_stall_br + 1;
            if (ex_stall)                    perf_stall_div <= perf_stall_div + 1;
            if (id_redirect)                 perf_taken     <= perf_taken + 1;
            if (trap_take)                   perf_traps     <= perf_traps + 1;
        end
    end
endmodule
