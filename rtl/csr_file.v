// Machine-mode CSR file (Zicsr) with trap entry / MRET and machine timer interrupt.
module csr_file (
    input         clk,
    input         rst,
    // CSR instruction port (EX stage)
    input         csr_en,            // a CSR instruction is in EX
    input  [11:0] addr,
    input  [1:0]  op,                // 01 = RW, 10 = RS, 11 = RC
    input  [31:0] wdata,
    input         do_write,          // false for CSRRS/RC with rs1/zimm == 0
    input         commit,            // the instruction really executes this cycle
    output reg [31:0] rdata,
    output        illegal,
    // trap interface
    input         trap_enter,
    input  [31:0] trap_epc,
    input  [31:0] trap_cause,
    input  [31:0] trap_val,
    input         mret_commit,
    output [31:0] mtvec_o,
    output [31:0] mepc_o,
    // interrupts / counters
    input         timer_irq,
    output        irq_pending,
    input         retire
);
    reg        mie_g, mpie, mtie;
    reg [31:0] mtvec, mscratch, mepc, mcause, mtval, mcycle, minstret;

    assign mtvec_o = mtvec;
    assign mepc_o  = mepc;
    assign irq_pending = mie_g & mtie & timer_irq;

    reg known;
    always @* begin
        known = 1'b1; rdata = 32'b0;
        case (addr)
            12'h300: rdata = {19'b0, 2'b11, 3'b0, mpie, 3'b0, mie_g, 3'b0};   // mstatus (MPP=M)
            12'h301: rdata = 32'h4000_1100;                                    // misa RV32IM
            12'h304: rdata = {24'b0, mtie, 7'b0};                              // mie
            12'h305: rdata = mtvec;
            12'h340: rdata = mscratch;
            12'h341: rdata = mepc;
            12'h342: rdata = mcause;
            12'h343: rdata = mtval;
            12'h344: rdata = {24'b0, timer_irq, 7'b0};                         // mip
            12'hB00, 12'hC00: rdata = mcycle;
            12'hB02, 12'hC02: rdata = minstret;
            12'hB80, 12'hB82, 12'hC80, 12'hC82: rdata = 32'b0;                 // upper halves
            12'hF11, 12'hF12, 12'hF13, 12'hF14: rdata = 32'b0;                 // vendor/arch/imp/hartid
            default: known = 1'b0;
        endcase
    end

    wire read_only = (addr[11:10] == 2'b11);
    assign illegal = csr_en && (!known || (do_write && read_only));

    reg [31:0] nv;
    always @* begin
        case (op)
            2'b01:   nv = wdata;
            2'b10:   nv = rdata | wdata;
            default: nv = rdata & ~wdata;
        endcase
    end

    wire wr = commit && csr_en && do_write && !illegal;

    always @(posedge clk) begin
        if (rst) begin
            mie_g <= 0; mpie <= 0; mtie <= 0; mtvec <= 0; mscratch <= 0;
            mepc <= 0; mcause <= 0; mtval <= 0; mcycle <= 0; minstret <= 0;
        end else begin
            mcycle <= mcycle + 1;
            if (retire) minstret <= minstret + 1;
            if (trap_enter) begin
                mepc <= trap_epc; mcause <= trap_cause; mtval <= trap_val;
                mpie <= mie_g;    mie_g  <= 1'b0;
            end else if (mret_commit) begin
                mie_g <= mpie;    mpie   <= 1'b1;
            end else if (wr) begin
                case (addr)
                    12'h300: begin mie_g <= nv[3]; mpie <= nv[7]; end
                    12'h304: mtie <= nv[7];
                    12'h305: mtvec <= {nv[31:2], 2'b00};      // direct mode only
                    12'h340: mscratch <= nv;
                    12'h341: mepc <= {nv[31:2], 2'b00};
                    12'h342: mcause <= nv;
                    12'h343: mtval <= nv;
                    12'hB00: mcycle <= nv;
                    12'hB02: minstret <= nv;
                    default: ;                                 // WARL: ignore writes (misa, mip, ...)
                endcase
            end
        end
    end
endmodule
