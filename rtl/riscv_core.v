// =============================================================================
// 5-stage pipelined RV32IM_Zicsr core (machine mode):  IF -> ID -> EX -> MEM -> WB
//
// Hazard handling
//   Data (RAW)    : EX/MEM->EX and MEM/WB->EX forwarding, WB->ID regfile write-through,
//                   1-cycle stall for load-use.
//   Control       : BTB + 2-bit counters predict in IF; branches/JAL/JALR resolve in EX;
//                   a misprediction flushes IF/ID + ID/EX (2-cycle penalty).
//   Structural    : Harvard memories (IF and MEM never collide); regfile write-through;
//                   the iterative divider is a non-pipelined unit => the front end stalls
//                   while it is busy and bubbles are inserted behind it.
//   Exceptions    : illegal instr, ECALL, EBREAK, misaligned fetch target / load / store,
//                   and machine timer interrupt are all taken precisely in EX
//                   (the faulting instruction never commits, younger ones are flushed).
// =============================================================================
module riscv_core #(parameter BTB_ENTRIES = 16) (
    input         clk,
    input         rst,
    // instruction memory
    output [31:0] imem_addr,
    input  [31:0] imem_rdata,
    // data / MMIO bus (MEM stage)
    output [31:0] dmem_addr,
    output [31:0] dmem_wdata,
    output [3:0]  dmem_be,
    output        dmem_we,
    input  [31:0] dmem_rdata,
    // interrupts / control
    input         irq_timer,
    input         stop,            // freeze performance counters (simulation end)
    // performance counters
    output reg [31:0] perf_cycles,
    output reg [31:0] perf_instret,
    output reg [31:0] perf_stall_lu,    // load-use stall cycles
    output reg [31:0] perf_stall_div,   // divider-busy stall cycles
    output reg [31:0] perf_flushes,     // pipeline redirects (mispredict/trap/mret)
    output reg [31:0] perf_branches,    // committed control-flow instructions
    output reg [31:0] perf_mispred,     // mispredicted control-flow instructions
    output reg [31:0] perf_traps
);
    localparam NOP = 32'h0000_0013;

    // ------------------------------------------------------------ global signals
    wire        load_use;            // load-use hazard detected in ID
    wire        ex_stall;            // divider busy
    wire        front_stall = load_use | ex_stall;
    wire        redirect;            // EX redirects fetch (mispredict / trap / mret)
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
        if (rst)              pc <= 32'b0;
        else if (redirect)    pc <= redirect_pc;
        else if (!front_stall) pc <= bp_taken ? bp_target : pc + 32'd4;
    end

    // ---------------------------------------------------------- IF/ID reg
    reg [31:0] ifid_pc, ifid_instr, ifid_pred_target;
    reg        ifid_valid, ifid_pred_taken;

    always @(posedge clk) begin
        if (rst || redirect) begin
            ifid_pc <= 0; ifid_instr <= NOP; ifid_valid <= 0;
            ifid_pred_taken <= 0; ifid_pred_target <= 0;
        end else if (!front_stall) begin
            ifid_pc <= pc; ifid_instr <= imem_rdata; ifid_valid <= 1;
            ifid_pred_taken <= bp_taken; ifid_pred_target <= bp_target;
        end
    end

    // ============================================================ ID stage
    wire c_reg_write, c_mem_read, c_mem_write, c_alu_src_imm, c_alu_src_pc;
    wire [3:0] c_alu_ctl;
    wire c_branch, c_jal, c_jalr, c_uses_rs1, c_uses_rs2;
    wire c_mul, c_div, c_csr, c_mret, c_ecall, c_ebreak, c_illegal;

    control_unit u_ctl (
        .instr(ifid_instr),
        .reg_write(c_reg_write), .mem_read(c_mem_read), .mem_write(c_mem_write),
        .alu_src_imm(c_alu_src_imm), .alu_src_pc(c_alu_src_pc), .alu_ctl(c_alu_ctl),
        .branch(c_branch), .jal(c_jal), .jalr(c_jalr),
        .uses_rs1(c_uses_rs1), .uses_rs2(c_uses_rs2),
        .is_mul(c_mul), .is_div(c_div), .is_csr(c_csr), .is_mret(c_mret),
        .is_ecall(c_ecall), .is_ebreak(c_ebreak), .illegal(c_illegal)
    );

    // operands that are not used read as x0 so they never create false hazards
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
               idex_illegal, idex_pred_taken;
    assign idex_pc_w = idex_pc;

    always @(posedge clk) begin
        if (rst || redirect || (load_use && !ex_stall)) begin
            // bubble
            idex_reg_write <= 0; idex_mem_read <= 0; idex_mem_write <= 0;
            idex_alu_src_imm <= 0; idex_alu_src_pc <= 0; idex_alu_ctl <= 0;
            idex_branch <= 0; idex_jal <= 0; idex_jalr <= 0; idex_valid <= 0;
            idex_mul <= 0; idex_div <= 0; idex_csr <= 0; idex_mret <= 0;
            idex_ecall <= 0; idex_ebreak <= 0; idex_illegal <= 0;
            idex_pred_taken <= 0; idex_pred_target <= 0;
            idex_rs1 <= 0; idex_rs2 <= 0; idex_rd <= 0; idex_f3 <= 0;
            idex_pc <= 0; idex_instr <= NOP; idex_rs1v <= 0; idex_rs2v <= 0; idex_imm <= 0;
        end else if (!ex_stall) begin
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
            idex_illegal     <= c_illegal & ifid_valid;
            idex_valid       <= ifid_valid;
            idex_pred_taken  <= ifid_pred_taken & ifid_valid;
            idex_pred_target <= ifid_pred_target;
            idex_rs1 <= id_rs1; idex_rs2 <= id_rs2; idex_rd <= id_rd;
            idex_f3  <= ifid_instr[14:12];
            idex_pc  <= ifid_pc; idex_instr <= ifid_instr;
            idex_rs1v <= id_rdata1; idex_rs2v <= id_rdata2; idex_imm <= id_imm;
        end
        // ex_stall: hold
    end

    // ---- load-use hazard detection (ID) ----
    hazard_unit u_haz (
        .idex_mem_read(idex_mem_read), .idex_rd(idex_rd),
        .id_rs1(id_rs1), .id_rs2(id_rs2), .stall(load_use)
    );

    // ============================================================ EX stage
    reg [31:0] exmem_result, exmem_store;
    reg [4:0]  exmem_rd;
    reg [2:0]  exmem_f3;
    reg        exmem_reg_write, exmem_mem_read, exmem_mem_write, exmem_valid;
    reg [4:0]  memwb_rd;
    reg        memwb_reg_write, memwb_valid;
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
        .clk(clk), .rst(rst), .start(div_start), .a(op_a), .b(op_b), .op(idex_f3[1:0]),
        .active(div_active), .done(div_done), .result(div_y)
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

    // ---- CSR file ----
    wire        csr_illegal, irq_pending;
    wire [31:0] csr_rdata, mtvec, mepc;
    wire        trap_take, mret_take;
    wire        csr_do_write = (idex_f3[1:0] == 2'b01) || (idex_instr[19:15] != 5'b0);
    wire [31:0] csr_wdata    = idex_f3[2] ? {27'b0, idex_instr[19:15]} : op_a;
    reg  [31:0] trap_cause, trap_val;

    csr_file u_csr (
        .clk(clk), .rst(rst),
        .csr_en(idex_csr), .addr(idex_instr[31:20]), .op(idex_f3[1:0]),
        .wdata(csr_wdata), .do_write(csr_do_write), .commit(!trap_take),
        .rdata(csr_rdata), .illegal(csr_illegal),
        .trap_enter(trap_take), .trap_epc(idex_pc), .trap_cause(trap_cause), .trap_val(trap_val),
        .mret_commit(mret_take), .mtvec_o(mtvec), .mepc_o(mepc),
        .timer_irq(irq_timer), .irq_pending(irq_pending), .retire(memwb_valid)
    );

    // ---- exceptions / interrupts (precise, taken in EX) ----
    wire exc_illegal   = idex_illegal | csr_illegal;
    wire exc_inst_mis  = taken_raw & is_ctrl & target_raw[1];
    wire exc_ld_mis    = idex_mem_read  & ((idex_f3[1:0] == 2'b01 & alu_y[0]) |
                                           (idex_f3[1:0] == 2'b10 & |alu_y[1:0]));
    wire exc_st_mis    = idex_mem_write & ((idex_f3[1:0] == 2'b01 & alu_y[0]) |
                                           (idex_f3[1:0] == 2'b10 & |alu_y[1:0]));
    wire exc_any       = exc_illegal | idex_ecall | idex_ebreak | exc_inst_mis | exc_ld_mis | exc_st_mis;
    wire irq_take      = idex_valid & irq_pending & ~div_active;
    assign trap_take   = irq_take | exc_any;
    assign mret_take   = idex_mret & ~trap_take;

    always @* begin
        trap_val = 32'b0;
        if (irq_take)          trap_cause = 32'h8000_0007;
        else if (exc_illegal)  begin trap_cause = 32'd2;  trap_val = idex_instr; end
        else if (idex_ecall)   trap_cause = 32'd11;
        else if (idex_ebreak)  trap_cause = 32'd3;
        else if (exc_inst_mis) begin trap_cause = 32'd0;  trap_val = target_raw; end
        else if (exc_ld_mis)   begin trap_cause = 32'd4;  trap_val = alu_y; end
        else                   begin trap_cause = 32'd6;  trap_val = alu_y; end
    end

    // ---- divider handshake / structural stall ----
    assign div_start = idex_div & ~div_active & ~div_done & ~trap_take;
    assign ex_stall  = idex_div & ~div_done & ~trap_take;
    wire   ex_commit = ~ex_stall & ~trap_take;      // instruction in EX really completes

    // ---- fetch redirect ----
    assign ex_actual_taken  = is_ctrl & taken_raw;
    assign ex_actual_target = target_raw;
    wire [31:0] actual_next = ex_actual_taken ? target_raw : (idex_pc + 32'd4);
    wire mispredict = ex_commit & idex_valid &
                      (is_ctrl ? ((ex_actual_taken != idex_pred_taken) ||
                                  (ex_actual_taken && idex_pred_target != target_raw))
                               : idex_pred_taken);
    assign redirect    = trap_take | mret_take | mispredict;
    assign redirect_pc = trap_take ? mtvec : mret_take ? mepc : actual_next;
    assign bp_upd_en   = ex_commit & is_ctrl;

    wire [31:0] ex_result = (idex_jal | idex_jalr) ? (idex_pc + 32'd4) :
                            idex_csr ? csr_rdata :
                            idex_mul ? mul_y :
                            idex_div ? div_y : alu_y;

    // --------------------------------------------------------- EX/MEM reg
    always @(posedge clk) begin
        if (rst || !ex_commit) begin
            exmem_result <= 0; exmem_store <= 0; exmem_rd <= 0; exmem_f3 <= 0;
            exmem_reg_write <= 0; exmem_mem_read <= 0; exmem_mem_write <= 0; exmem_valid <= 0;
        end else begin
            exmem_result    <= ex_result;
            exmem_store     <= op_b;
            exmem_rd        <= idex_rd;
            exmem_f3        <= idex_f3;
            exmem_reg_write <= idex_reg_write;
            exmem_mem_read  <= idex_mem_read;
            exmem_mem_write <= idex_mem_write;
            exmem_valid     <= idex_valid;
        end
    end

    // ============================================================ MEM stage
    wire [1:0] byte_off = exmem_result[1:0];
    assign dmem_addr = exmem_result;
    assign dmem_we   = exmem_mem_write;

    reg [3:0]  be;
    reg [31:0] wdata;
    always @* begin
        case (exmem_f3[1:0])
            2'b00:   begin be = 4'b0001 << byte_off;             wdata = {4{exmem_store[7:0]}};  end
            2'b01:   begin be = byte_off[1] ? 4'b1100 : 4'b0011; wdata = {2{exmem_store[15:0]}}; end
            default: begin be = 4'b1111;                         wdata = exmem_store;            end
        endcase
    end
    assign dmem_be    = be;
    assign dmem_wdata = wdata;

    wire [31:0] shifted = dmem_rdata >> {byte_off, 3'b000};
    reg  [31:0] load_data;
    always @* begin
        case (exmem_f3)
            3'b000:  load_data = {{24{shifted[7]}},  shifted[7:0]};
            3'b001:  load_data = {{16{shifted[15]}}, shifted[15:0]};
            3'b100:  load_data = {24'b0, shifted[7:0]};
            3'b101:  load_data = {16'b0, shifted[15:0]};
            default: load_data = dmem_rdata;
        endcase
    end

    // --------------------------------------------------------- MEM/WB reg
    reg [31:0] memwb_result, memwb_load;
    reg        memwb_mem_to_reg;

    always @(posedge clk) begin
        if (rst) begin
            memwb_result <= 0; memwb_load <= 0; memwb_rd <= 0;
            memwb_reg_write <= 0; memwb_mem_to_reg <= 0; memwb_valid <= 0;
        end else begin
            memwb_result     <= exmem_result;
            memwb_load       <= load_data;
            memwb_rd         <= exmem_rd;
            memwb_reg_write  <= exmem_reg_write;
            memwb_mem_to_reg <= exmem_mem_read;
            memwb_valid      <= exmem_valid;
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
        end else if (!stop) begin
            perf_cycles <= perf_cycles + 1;
            if (memwb_valid)            perf_instret   <= perf_instret + 1;
            if (load_use && !ex_stall)  perf_stall_lu  <= perf_stall_lu + 1;
            if (ex_stall)               perf_stall_div <= perf_stall_div + 1;
            if (redirect)               perf_flushes   <= perf_flushes + 1;
            if (ex_commit && is_ctrl)   perf_branches  <= perf_branches + 1;
            if (mispredict && is_ctrl)  perf_mispred   <= perf_mispred + 1;
            if (trap_take)              perf_traps     <= perf_traps + 1;
        end
    end
endmodule
