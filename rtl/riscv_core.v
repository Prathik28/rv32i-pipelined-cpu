// =============================================================================
// 5-stage pipelined RV32I core:  IF -> ID -> EX -> MEM -> WB
//
// Hazard handling
//   Data hazards (RAW)
//     * EX/MEM -> EX and MEM/WB -> EX forwarding           (forwarding_unit)
//     * WB -> ID write-through in the register file         (regfile)
//     * load-use: 1-cycle stall + forward from WB           (hazard_unit)
//   Control hazards
//     * predict-not-taken; branches/JAL/JALR resolved in EX,
//       taken => flush IF/ID and ID/EX (2-cycle penalty)
//   Structural hazards
//     * Harvard memories (separate instr/data) => IF and MEM never collide
//     * regfile read/write same cycle handled by write-through
//     * single ALU, single memory port per stage - no resource sharing
//   WAW/WAR cannot occur: in-order pipeline, writeback is in the last stage.
// =============================================================================
module riscv_core (
    input         clk,
    input         rst,
    // instruction memory
    output [31:0] imem_addr,
    input  [31:0] imem_rdata,
    // data memory
    output [31:0] dmem_addr,
    output [31:0] dmem_wdata,
    output [3:0]  dmem_be,
    output        dmem_we,
    input  [31:0] dmem_rdata,
    // status / performance counters
    output        halt,
    output reg [31:0] perf_cycles,
    output reg [31:0] perf_instret,
    output reg [31:0] perf_stalls,
    output reg [31:0] perf_flushes
);
    localparam NOP = 32'h0000_0013;

    // ------------------------------------------------------------------ wires
    wire        stall;            // load-use stall
    wire        branch_taken;     // redirect from EX
    wire [31:0] branch_target;
    wire        ex_system;        // ECALL/EBREAK reached EX
    reg         halted;

    // ============================================================ IF stage
    reg  [31:0] pc;
    assign imem_addr = pc;

    always @(posedge clk) begin
        if (rst)                        pc <= 32'b0;
        else if (branch_taken)          pc <= branch_target;
        else if (!stall && !halted && !ex_system) pc <= pc + 32'd4;
    end

    // ---------------------------------------------------------- IF/ID reg
    reg [31:0] ifid_pc, ifid_instr;
    reg        ifid_valid;

    always @(posedge clk) begin
        if (rst || branch_taken || ex_system || halted) begin
            ifid_pc <= 32'b0; ifid_instr <= NOP; ifid_valid <= 1'b0;
        end else if (!stall) begin
            ifid_pc <= pc; ifid_instr <= imem_rdata; ifid_valid <= 1'b1;
        end
        // stall: hold
    end

    // ============================================================ ID stage
    wire [4:0] id_rs1_raw = ifid_instr[19:15];
    wire [4:0] id_rs2_raw = ifid_instr[24:20];
    wire [4:0] id_rd      = ifid_instr[11:7];

    wire c_reg_write, c_mem_read, c_mem_write, c_alu_src_imm, c_alu_src_pc;
    wire [3:0] c_alu_ctl;
    wire c_branch, c_jal, c_jalr, c_system, c_uses_rs1, c_uses_rs2;

    control_unit u_ctl (
        .instr(ifid_instr),
        .reg_write(c_reg_write), .mem_read(c_mem_read), .mem_write(c_mem_write),
        .alu_src_imm(c_alu_src_imm), .alu_src_pc(c_alu_src_pc), .alu_ctl(c_alu_ctl),
        .branch(c_branch), .jal(c_jal), .jalr(c_jalr), .system(c_system),
        .uses_rs1(c_uses_rs1), .uses_rs2(c_uses_rs2)
    );

    // Operands that are not used read as x0 so they never cause false hazards
    wire [4:0] id_rs1 = c_uses_rs1 ? id_rs1_raw : 5'd0;
    wire [4:0] id_rs2 = c_uses_rs2 ? id_rs2_raw : 5'd0;

    wire [31:0] id_imm, id_rdata1, id_rdata2;
    imm_gen u_imm (.instr(ifid_instr), .imm(id_imm));

    // write-back signals (declared here, driven in WB stage)
    wire        wb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;

    regfile rf (
        .clk(clk), .we(wb_reg_write), .waddr(wb_rd), .wdata(wb_data),
        .raddr1(id_rs1), .raddr2(id_rs2), .rdata1(id_rdata1), .rdata2(id_rdata2)
    );

    // ---------------------------------------------------------- ID/EX reg
    reg [31:0] idex_pc, idex_rs1v, idex_rs2v, idex_imm;
    reg [4:0]  idex_rs1, idex_rs2, idex_rd;
    reg [2:0]  idex_f3;
    reg [3:0]  idex_alu_ctl;
    reg        idex_reg_write, idex_mem_read, idex_mem_write, idex_alu_src_imm,
               idex_alu_src_pc, idex_branch, idex_jal, idex_jalr, idex_system, idex_valid;

    wire id_bubble = rst || branch_taken || ex_system || stall || halted;

    always @(posedge clk) begin
        if (id_bubble) begin
            idex_reg_write <= 0; idex_mem_read <= 0; idex_mem_write <= 0;
            idex_alu_src_imm <= 0; idex_alu_src_pc <= 0; idex_alu_ctl <= 0;
            idex_branch <= 0; idex_jal <= 0; idex_jalr <= 0; idex_system <= 0;
            idex_valid <= 0;
            idex_rs1 <= 0; idex_rs2 <= 0; idex_rd <= 0; idex_f3 <= 0;
            idex_pc <= 0; idex_rs1v <= 0; idex_rs2v <= 0; idex_imm <= 0;
        end else begin
            idex_reg_write   <= c_reg_write & ifid_valid;
            idex_mem_read    <= c_mem_read  & ifid_valid;
            idex_mem_write   <= c_mem_write & ifid_valid;
            idex_alu_src_imm <= c_alu_src_imm;
            idex_alu_src_pc  <= c_alu_src_pc;
            idex_alu_ctl     <= c_alu_ctl;
            idex_branch      <= c_branch & ifid_valid;
            idex_jal         <= c_jal    & ifid_valid;
            idex_jalr        <= c_jalr   & ifid_valid;
            idex_system      <= c_system & ifid_valid;
            idex_valid       <= ifid_valid;
            idex_rs1 <= id_rs1; idex_rs2 <= id_rs2; idex_rd <= id_rd;
            idex_f3  <= ifid_instr[14:12];
            idex_pc  <= ifid_pc;
            idex_rs1v <= id_rdata1; idex_rs2v <= id_rdata2; idex_imm <= id_imm;
        end
    end

    // ---- load-use hazard detection (ID) ----
    hazard_unit u_haz (
        .idex_mem_read(idex_mem_read), .idex_rd(idex_rd),
        .id_rs1(id_rs1), .id_rs2(id_rs2), .stall(stall)
    );

    // ============================================================ EX stage
    wire [1:0] fwd_a, fwd_b;
    // EX/MEM and MEM/WB regs (declared below)
    reg [31:0] exmem_result, exmem_store;
    reg [4:0]  exmem_rd;
    reg [2:0]  exmem_f3;
    reg        exmem_reg_write, exmem_mem_read, exmem_mem_write, exmem_system, exmem_valid;
    reg [4:0]  memwb_rd;
    reg        memwb_reg_write;

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

    // branch comparator (uses forwarded operands)
    wire eq  = (op_a == op_b);
    wire lt  = ($signed(op_a) < $signed(op_b));
    wire ltu = (op_a < op_b);
    reg  cond;
    always @* begin
        case (idex_f3)
            3'b000:  cond = eq;     // BEQ
            3'b001:  cond = ~eq;    // BNE
            3'b100:  cond = lt;     // BLT
            3'b101:  cond = ~lt;    // BGE
            3'b110:  cond = ltu;    // BLTU
            3'b111:  cond = ~ltu;   // BGEU
            default: cond = 1'b0;
        endcase
    end

    assign branch_taken  = idex_jal | idex_jalr | (idex_branch & cond);
    assign branch_target = idex_jalr ? (alu_y & 32'hFFFF_FFFE) : (idex_pc + idex_imm);
    assign ex_system     = idex_system;

    wire [31:0] ex_result = (idex_jal | idex_jalr) ? (idex_pc + 32'd4) : alu_y;

    // --------------------------------------------------------- EX/MEM reg
    always @(posedge clk) begin
        if (rst) begin
            exmem_result <= 0; exmem_store <= 0; exmem_rd <= 0; exmem_f3 <= 0;
            exmem_reg_write <= 0; exmem_mem_read <= 0; exmem_mem_write <= 0;
            exmem_system <= 0; exmem_valid <= 0;
        end else begin
            exmem_result    <= ex_result;
            exmem_store     <= op_b;          // forwarded store data
            exmem_rd        <= idex_rd;
            exmem_f3        <= idex_f3;
            exmem_reg_write <= idex_reg_write;
            exmem_mem_read  <= idex_mem_read;
            exmem_mem_write <= idex_mem_write;
            exmem_system    <= idex_system;
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
            2'b00:   begin be = 4'b0001 << byte_off;           wdata = {4{exmem_store[7:0]}};  end // SB
            2'b01:   begin be = byte_off[1] ? 4'b1100 : 4'b0011; wdata = {2{exmem_store[15:0]}}; end // SH
            default: begin be = 4'b1111;                       wdata = exmem_store;            end // SW
        endcase
    end
    assign dmem_be    = be;
    assign dmem_wdata = wdata;

    // load alignment + sign/zero extension
    wire [31:0] shifted = dmem_rdata >> {byte_off, 3'b000};
    reg  [31:0] load_data;
    always @* begin
        case (exmem_f3)
            3'b000:  load_data = {{24{shifted[7]}},  shifted[7:0]};   // LB
            3'b001:  load_data = {{16{shifted[15]}}, shifted[15:0]};  // LH
            3'b100:  load_data = {24'b0, shifted[7:0]};               // LBU
            3'b101:  load_data = {16'b0, shifted[15:0]};              // LHU
            default: load_data = dmem_rdata;                          // LW
        endcase
    end

    // --------------------------------------------------------- MEM/WB reg
    reg [31:0] memwb_result, memwb_load;
    reg        memwb_mem_to_reg, memwb_system, memwb_valid;

    always @(posedge clk) begin
        if (rst) begin
            memwb_result <= 0; memwb_load <= 0; memwb_rd <= 0;
            memwb_reg_write <= 0; memwb_mem_to_reg <= 0; memwb_system <= 0; memwb_valid <= 0;
        end else begin
            memwb_result     <= exmem_result;
            memwb_load       <= load_data;
            memwb_rd         <= exmem_rd;
            memwb_reg_write  <= exmem_reg_write;
            memwb_mem_to_reg <= exmem_mem_read;
            memwb_system     <= exmem_system;
            memwb_valid      <= exmem_valid;
        end
    end

    // ============================================================ WB stage
    assign wb_data      = memwb_mem_to_reg ? memwb_load : memwb_result;
    assign wb_rd        = memwb_rd;
    assign wb_reg_write = memwb_reg_write;
    assign halt         = memwb_system;

    // ---------------------------------------------------------- bookkeeping
    always @(posedge clk) begin
        if (rst) halted <= 1'b0;
        else if (ex_system) halted <= 1'b1;
    end

    always @(posedge clk) begin
        if (rst) begin
            perf_cycles <= 0; perf_instret <= 0; perf_stalls <= 0; perf_flushes <= 0;
        end else if (!memwb_system) begin
            perf_cycles  <= perf_cycles + 1;
            if (memwb_valid)   perf_instret <= perf_instret + 1;
            if (stall)         perf_stalls  <= perf_stalls + 1;
            if (branch_taken)  perf_flushes <= perf_flushes + 1;
        end
    end
endmodule
