// =============================================================================
// 5-stage pipelined RV32IMA_Zicsr core (M + U privilege levels, PMP):  IF -> ID -> EX -> MEM -> WB
//
// Hazard handling
//   Data (RAW)    : EX/MEM->EX and MEM/WB->EX forwarding, WB->ID regfile write-through,
//                   1-cycle stall for load-use (loads, LR, SC and AMOs all return data from MEM).
//   Control       : BTB + 2-bit counters predict in IF; branches/JAL/JALR resolve in EX;
//                   a misprediction flushes IF/ID + ID/EX. FENCE.I flushes the front end.
//   Structural    : Harvard memories; regfile write-through; the iterative divider and a
//                   memory stage that can take several cycles (wait states, misaligned accesses
//                   split in two, atomic read-modify-write) freeze the pipeline in place.
//   Exceptions    : fetch/load/store access faults (address map + PMP), illegal instruction,
//                   ECALL (U/M), EBREAK, misaligned jump target / MMIO access / atomic, and
//                   machine software/timer/external interrupts. All are taken precisely in EX:
//                   the faulting instruction never commits, younger ones are flushed.
// =============================================================================
module riscv_core #(parameter BTB_ENTRIES = 16) (
    input         clk,
    input         rst,
    // instruction memory
    output [31:0] imem_addr,
    input  [31:0] imem_rdata,
    // data bus (MEM stage): word-aligned address, byte enables, request/ready handshake
    output        dmem_req,
    output        dmem_we,
    output [31:0] dmem_addr,
    output [31:0] dmem_wdata,
    output [3:0]  dmem_be,
    input  [31:0] dmem_rdata,
    input         dmem_ready,
    // interrupts / time
    input         irq_timer,
    input         irq_soft,
    input         irq_ext,
    input  [63:0] mtime,
    input         stop,            // freeze performance counters (simulation end)
    // performance counters
    output reg [31:0] perf_cycles,
    output reg [31:0] perf_instret,
    output reg [31:0] perf_stall_lu,    // load-use stall cycles
    output reg [31:0] perf_stall_div,   // divider-busy stall cycles
    output reg [31:0] perf_flushes,     // pipeline redirects (mispredict/trap/mret/fence.i)
    output reg [31:0] perf_branches,    // committed control-flow instructions
    output reg [31:0] perf_mispred,     // mispredicted control-flow instructions
    output reg [31:0] perf_traps,
    output reg [31:0] perf_stall_mem    // cycles the pipeline was frozen by the memory stage
);
    localparam NOP = 32'h0000_0013;

    // ------------------------------------------------------------ global signals
    wire        mem_hold;            // MEM stage not finished: freeze IF..EX/MEM
    wire        ex_active = ~mem_hold;
    wire        load_use;            // load-use hazard detected in ID
    wire        ex_stall;            // divider busy
    wire        front_stall = load_use | ex_stall;
    wire        redirect;            // EX redirects fetch (mispredict / trap / mret / fence.i)
    wire [31:0] redirect_pc;

    // ============================================================ IF stage
    reg  [31:0] pc;
    assign imem_addr = pc;

    wire        bp_taken;
    wire [31:0] bp_target;
    wire        bp_upd_en, ex_actual_taken;
    wire [31:0] ex_actual_target;
    wire [31:0] idex_pc_w;

    branch_predictor #(.ENTRIES(BTB_ENTRIES)) u_bp (
        .clk(clk), .rst(rst), .lookup_pc(pc),
        .pred_taken(bp_taken), .pred_target(bp_target),
        .upd_en(bp_upd_en), .upd_pc(idex_pc_w),
        .upd_taken(ex_actual_taken), .upd_target(ex_actual_target)
    );

    always @(posedge clk) begin
        if (rst)               pc <= 32'b0;
        else if (mem_hold)     ;
        else if (redirect)     pc <= redirect_pc;
        else if (!front_stall) pc <= bp_taken ? bp_target : pc + 32'd4;
    end

    // ---------------------------------------------------------- IF/ID reg
    reg [31:0] ifid_pc, ifid_instr, ifid_pred_target;
    reg        ifid_valid, ifid_pred_taken;

    always @(posedge clk) begin
        if (rst || (redirect && !mem_hold)) begin
            ifid_pc <= 0; ifid_instr <= NOP; ifid_valid <= 0;
            ifid_pred_taken <= 0; ifid_pred_target <= 0;
        end else if (!mem_hold && !front_stall) begin
            ifid_pc <= pc; ifid_instr <= imem_rdata; ifid_valid <= 1;
            ifid_pred_taken <= bp_taken; ifid_pred_target <= bp_target;
        end
    end

    // ============================================================ ID stage
    wire c_reg_write, c_mem_read, c_mem_write, c_alu_src_imm, c_alu_src_pc;
    wire [3:0] c_alu_ctl;
    wire c_branch, c_jal, c_jalr, c_uses_rs1, c_uses_rs2;
    wire c_mul, c_div, c_csr, c_mret, c_ecall, c_ebreak, c_amo, c_fencei, c_illegal;

    control_unit u_ctl (
        .instr(ifid_instr),
        .reg_write(c_reg_write), .mem_read(c_mem_read), .mem_write(c_mem_write),
        .alu_src_imm(c_alu_src_imm), .alu_src_pc(c_alu_src_pc), .alu_ctl(c_alu_ctl),
        .branch(c_branch), .jal(c_jal), .jalr(c_jalr),
        .uses_rs1(c_uses_rs1), .uses_rs2(c_uses_rs2),
        .is_mul(c_mul), .is_div(c_div), .is_csr(c_csr), .is_mret(c_mret),
        .is_ecall(c_ecall), .is_ebreak(c_ebreak), .is_amo(c_amo), .is_fencei(c_fencei),
        .illegal(c_illegal)
    );

    wire [4:0] id_rs1 = c_uses_rs1 ? ifid_instr[19:15] : 5'd0;
    wire [4:0] id_rs2 = c_uses_rs2 ? ifid_instr[24:20] : 5'd0;
    wire [4:0] id_rd  = ifid_instr[11:7];

    wire [31:0] id_imm, id_rdata1, id_rdata2;
    imm_gen u_imm (.instr(ifid_instr), .imm(id_imm));

    wire        wb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;

    regfile rf (
        .clk(clk), .we(wb_reg_write), .waddr(wb_rd), .wdata(wb_data),
        .raddr1(id_rs1), .raddr2(id_rs2), .rdata1(id_rdata1), .rdata2(id_rdata2)
    );

    // ---------------------------------------------------------- ID/EX reg
    reg [31:0] idex_pc, idex_instr, idex_rs1v, idex_rs2v, idex_imm, idex_pred_target;
    reg [4:0]  idex_rs1, idex_rs2, idex_rd;
    reg [2:0]  idex_f3;
    reg [3:0]  idex_alu_ctl;
    reg        idex_reg_write, idex_mem_read, idex_mem_write, idex_alu_src_imm,
               idex_alu_src_pc, idex_branch, idex_jal, idex_jalr, idex_valid,
               idex_mul, idex_div, idex_csr, idex_mret, idex_ecall, idex_ebreak,
               idex_amo, idex_fencei, idex_illegal, idex_pred_taken;
    assign idex_pc_w = idex_pc;

    always @(posedge clk) begin
        if (rst || (!mem_hold && (redirect || (load_use && !ex_stall)))) begin
            // bubble
            idex_reg_write <= 0; idex_mem_read <= 0; idex_mem_write <= 0;
            idex_alu_src_imm <= 0; idex_alu_src_pc <= 0; idex_alu_ctl <= 0;
            idex_branch <= 0; idex_jal <= 0; idex_jalr <= 0; idex_valid <= 0;
            idex_mul <= 0; idex_div <= 0; idex_csr <= 0; idex_mret <= 0;
            idex_ecall <= 0; idex_ebreak <= 0; idex_illegal <= 0; idex_amo <= 0; idex_fencei <= 0;
            idex_pred_taken <= 0; idex_pred_target <= 0;
            idex_rs1 <= 0; idex_rs2 <= 0; idex_rd <= 0; idex_f3 <= 0;
            idex_pc <= 0; idex_instr <= NOP; idex_rs1v <= 0; idex_rs2v <= 0; idex_imm <= 0;
        end else if (!mem_hold && !ex_stall) begin
            idex_reg_write   <= c_reg_write & ifid_valid;
            idex_mem_read    <= c_mem_read  & ifid_valid;
            idex_mem_write   <= c_mem_write & ifid_valid;
            idex_alu_src_imm <= c_alu_src_imm;
            idex_alu_src_pc  <= c_alu_src_pc;
            idex_alu_ctl     <= c_alu_ctl;
            idex_branch      <= c_branch & ifid_valid;
            idex_jal         <= c_jal    & ifid_valid;
            idex_jalr        <= c_jalr   & ifid_valid;
            idex_mul         <= c_mul    & ifid_valid;
            idex_div         <= c_div    & ifid_valid;
            idex_csr         <= c_csr    & ifid_valid;
            idex_mret        <= c_mret   & ifid_valid;
            idex_ecall       <= c_ecall  & ifid_valid;
            idex_ebreak      <= c_ebreak & ifid_valid;
            idex_amo         <= c_amo    & ifid_valid;
            idex_fencei      <= c_fencei & ifid_valid;
            idex_illegal     <= c_illegal & ifid_valid;
            idex_valid       <= ifid_valid;
            idex_pred_taken  <= ifid_pred_taken & ifid_valid;
            idex_pred_target <= ifid_pred_target;
            idex_rs1 <= id_rs1; idex_rs2 <= id_rs2; idex_rd <= id_rd;
            idex_f3  <= ifid_instr[14:12];
            idex_pc  <= ifid_pc; idex_instr <= ifid_instr;
            idex_rs1v <= id_rdata1; idex_rs2v <= id_rdata2; idex_imm <= id_imm;
        end
        // mem_hold / ex_stall: hold
    end

    hazard_unit u_haz (
        .idex_mem_read(idex_mem_read), .idex_rd(idex_rd),
        .id_rs1(id_rs1), .id_rs2(id_rs2), .stall(load_use)
    );

    // ============================================================ EX stage
    reg [31:0] exmem_result, exmem_store;
    reg [4:0]  exmem_rd, exmem_f5;
    reg [2:0]  exmem_f3;
    reg        exmem_reg_write, exmem_mem_read, exmem_mem_write, exmem_amo, exmem_valid;
    reg [4:0]  memwb_rd;
    reg        memwb_reg_write, memwb_valid, memwb_fresh;
    wire [1:0] fwd_a, fwd_b;

    forwarding_unit u_fwd (
        .idex_rs1(idex_rs1), .idex_rs2(idex_rs2),
        .exmem_rd(exmem_rd), .exmem_reg_write(exmem_reg_write),
        .memwb_rd(memwb_rd), .memwb_reg_write(memwb_reg_write),
        .fwd_a(fwd_a), .fwd_b(fwd_b)
    );

    wire [31:0] op_a = (fwd_a == 2'b10) ? exmem_result :
                       (fwd_a == 2'b01) ? wb_data      : idex_rs1v;
    wire [31:0] op_b = (fwd_b == 2'b10) ? exmem_result :
                       (fwd_b == 2'b01) ? wb_data      : idex_rs2v;

    wire [31:0] alu_a = idex_alu_src_pc  ? idex_pc  : op_a;
    wire [31:0] alu_b = idex_alu_src_imm ? idex_imm : op_b;
    wire [31:0] alu_y;
    alu u_alu (.a(alu_a), .b(alu_b), .ctl(idex_alu_ctl), .y(alu_y));

    // ---- multiply / divide ----
    wire [31:0] mul_y;
    mul_unit u_mul (.a(op_a), .b(op_b), .op(idex_f3[1:0]), .y(mul_y));

    wire        div_active, div_done, div_start;
    wire [31:0] div_y;
    div_unit u_div (
        .clk(clk), .rst(rst), .en(ex_active), .start(div_start), .a(op_a), .b(op_b),
        .op(idex_f3[1:0]), .active(div_active), .done(div_done), .result(div_y)
    );

    // ---- branch resolution ----
    wire eq  = (op_a == op_b);
    wire lt  = ($signed(op_a) < $signed(op_b));
    wire ltu = (op_a < op_b);
    reg  cond;
    always @* begin
        case (idex_f3)
            3'b000:  cond = eq;     3'b001: cond = ~eq;
            3'b100:  cond = lt;     3'b101: cond = ~lt;
            3'b110:  cond = ltu;    3'b111: cond = ~ltu;
            default: cond = 1'b0;
        endcase
    end
    wire is_ctrl      = idex_branch | idex_jal | idex_jalr;
    wire taken_raw    = idex_jal | idex_jalr | (idex_branch & cond);
    wire [31:0] target_raw = idex_jalr ? (alu_y & 32'hFFFF_FFFE) : (idex_pc + idex_imm);

    // ---- CSR file / privilege ----
    wire        csr_illegal, irq_pending;
    wire [31:0] csr_rdata, mtvec, mepc, irq_cause, pmpcfg;
    wire [127:0] pmpaddr;
    wire [1:0]  priv;
    wire        trap_take, mret_take, ex_commit;
    wire        csr_do_write = (idex_f3[1:0] == 2'b01) || (idex_instr[19:15] != 5'b0);
    wire [31:0] csr_wdata    = idex_f3[2] ? {27'b0, idex_instr[19:15]} : op_a;
    reg  [31:0] trap_cause, trap_val;

    csr_file u_csr (
        .clk(clk), .rst(rst),
        .csr_en(idex_csr), .addr(idex_instr[31:20]), .op(idex_f3[1:0]),
        .wdata(csr_wdata), .do_write(csr_do_write), .commit(ex_commit),
        .rdata(csr_rdata), .illegal(csr_illegal),
        .trap_enter(trap_take), .trap_epc(idex_pc), .trap_cause(trap_cause), .trap_val(trap_val),
        .mret_commit(mret_take), .priv_o(priv), .mtvec_o(mtvec), .mepc_o(mepc),
        .timer_irq(irq_timer), .soft_irq(irq_soft), .ext_irq(irq_ext), .mtime_i(mtime),
        .irq_pending(irq_pending), .irq_cause(irq_cause),
        .retire(memwb_valid & memwb_fresh),
        .pmpcfg_o(pmpcfg), .pmpaddr_o(pmpaddr)
    );

    // ---- memory-address checks (EX): address map, PMP, alignment ----
    wire        is_lr      = idex_amo & (idex_instr[31:27] == 5'b00010);
    wire        mem_any    = idex_mem_read | idex_mem_write;
    wire [2:0]  msz        = 3'd1 << idex_f3[1:0];                  // 1, 2 or 4 bytes
    wire [31:0] ea         = alu_y;
    wire [31:0] ea_end     = ea + {29'b0, msz} - 32'd1;

    // regions: 1 = RAM, 2 = slow RAM, 3 = instruction RAM (data port), 4 = MMIO, 0 = none
    function [2:0] region(input [31:0] a);
        if      (a[31:12] == 20'h00000) region = 3'd1;
        else if (a[31:12] == 20'h20000) region = 3'd2;
        else if (a[31:12] == 20'h30000) region = 3'd3;
        else if (a[31:8]  == 24'h100000) region = 3'd4;
        else                            region = 3'd0;
    endfunction
    wire [2:0] r_lo = region(ea);
    wire [2:0] r_hi = region(ea_end);
    wire region_ok  = (r_lo != 3'd0) && (r_lo == r_hi);
    wire amo_region = (r_lo == 3'd1) || (r_lo == 3'd2);
    wire misal      = |(ea & ({29'b0, msz} - 32'd1));

    wire d_r_ok, d_w_ok, d_x_unused, f_r_unused, f_w_unused, f_x_ok;
    pmp_check u_pmp_d (.priv(priv), .cfg(pmpcfg), .pa(pmpaddr), .lo(ea), .hi(ea_end),
                       .r_ok(d_r_ok), .w_ok(d_w_ok), .x_ok(d_x_unused));
    pmp_check u_pmp_f (.priv(priv), .cfg(pmpcfg), .pa(pmpaddr), .lo(idex_pc), .hi(idex_pc + 32'd3),
                       .r_ok(f_r_unused), .w_ok(f_w_unused), .x_ok(f_x_ok));

    wire fetch_fault = idex_valid & ((idex_pc[31:12] != 20'b0) | ~f_x_ok);
    wire acc_fault   = mem_any & (~region_ok | (idex_amo & ~amo_region) |
                                  (idex_mem_read & ~d_r_ok) | (idex_mem_write & ~d_w_ok));
    wire mis_trap    = mem_any & region_ok & ~acc_fault &
                       ((idex_amo & misal) | (~idex_amo & (r_lo == 3'd4) & misal));

    // ---- exceptions / interrupts (precise, taken in EX) ----
    wire exc_illegal   = idex_illegal | csr_illegal | (idex_mret & (priv != 2'b11));
    wire exc_inst_mis  = taken_raw & is_ctrl & target_raw[1];
    wire exc_any       = fetch_fault | exc_illegal | idex_ecall | idex_ebreak | exc_inst_mis |
                         acc_fault | mis_trap;
    wire irq_take      = idex_valid & irq_pending & ~div_active;
    assign trap_take   = ex_active & (irq_take | exc_any);
    assign mret_take   = idex_mret & ex_commit;

    always @* begin
        trap_val = 32'b0;
        if (irq_take)           trap_cause = irq_cause;
        else if (fetch_fault)   begin trap_cause = 32'd1;  trap_val = idex_pc; end
        else if (exc_illegal)   begin trap_cause = 32'd2;  trap_val = idex_instr; end
        else if (idex_ecall)    trap_cause = (priv == 2'b11) ? 32'd11 : 32'd8;
        else if (idex_ebreak)   trap_cause = 32'd3;
        else if (exc_inst_mis)  begin trap_cause = 32'd0;  trap_val = target_raw; end
        else if (acc_fault)     begin trap_cause = idex_mem_write ? 32'd7 : 32'd5; trap_val = ea; end
        else                    begin trap_cause = idex_mem_write ? 32'd6 : 32'd4; trap_val = ea; end
    end

    // ---- divider handshake / structural stall ----
    assign div_start = ex_active & idex_div & ~div_active & ~div_done & ~trap_take;
    assign ex_stall  = idex_div & ~div_done & ~trap_take;
    assign ex_commit = ex_active & ~ex_stall & ~trap_take;      // instruction in EX really completes

    // ---- fetch redirect ----
    assign ex_actual_taken  = is_ctrl & taken_raw;
    assign ex_actual_target = target_raw;
    wire [31:0] actual_next = ex_actual_taken ? target_raw : (idex_pc + 32'd4);
    wire mispredict = ex_commit & idex_valid &
                      (is_ctrl ? ((ex_actual_taken != idex_pred_taken) ||
                                  (ex_actual_taken && idex_pred_target != target_raw))
                               : idex_pred_taken);
    wire fencei_take = idex_fencei & ex_commit;
    wire vec_irq     = irq_take & mtvec[0];
    wire [31:0] trap_target = vec_irq ? ({mtvec[31:2], 2'b00} + {25'b0, irq_cause[4:0], 2'b00})
                                      :  {mtvec[31:2], 2'b00};
    assign redirect    = trap_take | mret_take | fencei_take | mispredict;
    assign redirect_pc = trap_take ? trap_target : mret_take ? mepc :
                         fencei_take ? (idex_pc + 32'd4) : actual_next;
    assign bp_upd_en   = ex_commit & is_ctrl;

    wire [31:0] ex_result = (idex_jal | idex_jalr) ? (idex_pc + 32'd4) :
                            idex_csr ? csr_rdata :
                            idex_mul ? mul_y :
                            idex_div ? div_y : alu_y;

    // --------------------------------------------------------- EX/MEM reg
    always @(posedge clk) begin
        if (rst || (!mem_hold && !ex_commit)) begin
            exmem_result <= 0; exmem_store <= 0; exmem_rd <= 0; exmem_f3 <= 0; exmem_f5 <= 0;
            exmem_reg_write <= 0; exmem_mem_read <= 0; exmem_mem_write <= 0; exmem_amo <= 0;
            exmem_valid <= 0;
        end else if (!mem_hold) begin
            exmem_result    <= ex_result;
            exmem_store     <= op_b;
            exmem_rd        <= idex_rd;
            exmem_f3        <= idex_f3;
            exmem_f5        <= idex_instr[31:27];
            exmem_reg_write <= idex_reg_write;
            exmem_mem_read  <= idex_mem_read;
            exmem_mem_write <= idex_mem_write;
            exmem_amo       <= idex_amo;
            exmem_valid     <= idex_valid;
        end
    end

    // ============================================================ MEM stage
    // One memory operation = 1 or 2 bus transactions ("phases"):
    //   plain access        : 1 phase, or 2 when it straddles a word boundary (misaligned)
    //   LR                  : 1 read          SC : 1 write if the reservation holds, else none
    //   AMO read-modify-write: phase 0 read, phase 1 write of the combined value
    // The pipeline is frozen (mem_hold) until the last phase has been accepted (dmem_ready).
    reg         mphase;
    reg  [31:0] lo_data;
    reg         resv_valid;
    reg  [29:0] resv_word;

    wire [1:0]  off      = exmem_result[1:0];
    wire [2:0]  sz       = 3'd1 << exmem_f3[1:0];
    wire        m_op     = exmem_mem_read | exmem_mem_write;
    wire        crossing = ~exmem_amo & (({1'b0, off} + sz) > 3'd4);
    wire        m_lr     = exmem_amo & (exmem_f5 == 5'b00010);
    wire        m_sc     = exmem_amo & (exmem_f5 == 5'b00011);
    wire        m_rmw    = exmem_amo & ~m_lr & ~m_sc;
    wire        sc_ok    = m_sc & resv_valid & (resv_word == exmem_result[31:2]);
    wire        sc_fail  = m_sc & ~sc_ok;

    wire        last_phase = (crossing | m_rmw) ? mphase : 1'b1;
    wire        bus_we   = (exmem_mem_write & ~exmem_amo) | sc_ok | (m_rmw & mphase);
    assign dmem_req  = m_op & ~sc_fail;
    assign dmem_we   = bus_we;
    wire        m_done   = ~m_op | sc_fail | (dmem_ready & last_phase);
    assign mem_hold  = ~m_done;

    // AMO ALU (old value = lo_data, operand = rs2)
    reg [31:0] amo_new;
    always @* begin
        case (exmem_f5)
            5'b00001: amo_new = exmem_store;                                        // SWAP
            5'b00000: amo_new = lo_data + exmem_store;                              // ADD
            5'b00100: amo_new = lo_data ^ exmem_store;                              // XOR
            5'b01100: amo_new = lo_data & exmem_store;                              // AND
            5'b01000: amo_new = lo_data | exmem_store;                              // OR
            5'b10000: amo_new = ($signed(lo_data) < $signed(exmem_store)) ? lo_data : exmem_store; // MIN
            5'b10100: amo_new = ($signed(lo_data) < $signed(exmem_store)) ? exmem_store : lo_data; // MAX
            5'b11000: amo_new = (lo_data < exmem_store) ? lo_data : exmem_store;    // MINU
            default:  amo_new = (lo_data < exmem_store) ? exmem_store : lo_data;    // MAXU
        endcase
    end

    // store data / byte enables, positioned in a 64-bit window (first word, second word)
    wire [31:0] st_mask = (sz == 3'd1) ? 32'h0000_00FF : (sz == 3'd2) ? 32'h0000_FFFF : 32'hFFFF_FFFF;
    wire [63:0] wd64    = {32'b0, exmem_store & st_mask} << {off, 3'b000};
    wire [3:0]  be_base = (sz == 3'd1) ? 4'b0001 : (sz == 3'd2) ? 4'b0011 : 4'b1111;
    wire [7:0]  be64    = {4'b0, be_base} << off;

    assign dmem_addr  = {exmem_result[31:2], 2'b00} + ((crossing & mphase) ? 32'd4 : 32'd0);
    assign dmem_wdata = m_rmw ? amo_new : exmem_amo ? exmem_store : (mphase ? wd64[63:32] : wd64[31:0]);
    assign dmem_be    = exmem_amo ? 4'b1111 : (mphase ? be64[7:4] : be64[3:0]);

    // load data: align (and join two words when misaligned) then sign/zero extend
    wire [63:0] join64  = crossing ? {dmem_rdata, lo_data} : {32'b0, dmem_rdata};
    wire [31:0] shifted = (join64 >> {off, 3'b000});
    reg  [31:0] load_data;
    always @* begin
        if (m_sc)       load_data = {31'b0, sc_fail};
        else if (m_rmw) load_data = lo_data;                 // old value
        else if (m_lr)  load_data = dmem_rdata;
        else begin
            case (exmem_f3)
                3'b000:  load_data = {{24{shifted[7]}},  shifted[7:0]};
                3'b001:  load_data = {{16{shifted[15]}}, shifted[15:0]};
                3'b100:  load_data = {24'b0, shifted[7:0]};
                3'b101:  load_data = {16'b0, shifted[15:0]};
                default: load_data = shifted;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            mphase <= 1'b0; lo_data <= 32'b0; resv_valid <= 1'b0; resv_word <= 30'b0;
        end else begin
            if (m_done) mphase <= 1'b0;
            else if (dmem_ready) begin mphase <= 1'b1; lo_data <= dmem_rdata; end
            if (m_done && m_lr) begin resv_valid <= 1'b1; resv_word <= exmem_result[31:2]; end
            if (m_done && m_sc) resv_valid <= 1'b0;
            if (trap_take)      resv_valid <= 1'b0;          // trap entry cancels a reservation
        end
    end

    // --------------------------------------------------------- MEM/WB reg
    // While the MEM stage is held, MEM/WB keeps its (already retired) instruction so that
    // forwarding sources do not vanish under a frozen EX stage; `memwb_fresh` avoids re-counting it.
    reg [31:0] memwb_result, memwb_load;
    reg        memwb_mem_to_reg;

    always @(posedge clk) begin
        if (rst) begin
            memwb_result <= 0; memwb_load <= 0; memwb_rd <= 0;
            memwb_reg_write <= 0; memwb_mem_to_reg <= 0; memwb_valid <= 0; memwb_fresh <= 0;
        end else if (mem_hold) begin
            memwb_fresh <= 1'b0;
        end else begin
            memwb_result     <= exmem_result;
            memwb_load       <= load_data;
            memwb_rd         <= exmem_rd;
            memwb_reg_write  <= exmem_reg_write;
            memwb_mem_to_reg <= exmem_mem_read;
            memwb_valid      <= exmem_valid;
            memwb_fresh      <= 1'b1;
        end
    end

    // ============================================================ WB stage
    assign wb_data      = memwb_mem_to_reg ? memwb_load : memwb_result;
    assign wb_rd        = memwb_rd;
    assign wb_reg_write = memwb_reg_write;

    // ---------------------------------------------------- performance counters
    always @(posedge clk) begin
        if (rst) begin
            perf_cycles <= 0; perf_instret <= 0; perf_stall_lu <= 0; perf_stall_div <= 0;
            perf_flushes <= 0; perf_branches <= 0; perf_mispred <= 0; perf_traps <= 0;
            perf_stall_mem <= 0;
        end else if (!stop) begin
            perf_cycles <= perf_cycles + 1;
            if (memwb_valid && memwb_fresh)  perf_instret   <= perf_instret + 1;
            if (load_use && !ex_stall && ex_active) perf_stall_lu <= perf_stall_lu + 1;
            if (ex_stall && ex_active)       perf_stall_div <= perf_stall_div + 1;
            if (mem_hold)                    perf_stall_mem <= perf_stall_mem + 1;
            if (redirect)                    perf_flushes   <= perf_flushes + 1;
            if (ex_commit && is_ctrl)        perf_branches  <= perf_branches + 1;
            if (mispredict && is_ctrl)       perf_mispred   <= perf_mispred + 1;
            if (trap_take)                   perf_traps     <= perf_traps + 1;
        end
    end
endmodule
