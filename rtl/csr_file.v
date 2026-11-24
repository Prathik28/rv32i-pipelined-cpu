// Machine/User-mode CSR file (Zicsr), PMP registers, 3 interrupt sources, 64-bit counters.
//   priv: 2'b00 = U-mode, 2'b11 = M-mode
module csr_file (
    input         clk,
    input         rst,
    // CSR instruction port (EX stage)
    input         csr_en,
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
    output [1:0]  priv_o,
    output [31:0] mtvec_o,           // bit0 = vectored mode
    output [31:0] mepc_o,
    // interrupts / counters
    input         timer_irq,
    input         soft_irq,
    input         ext_irq,
    input  [63:0] mtime_i,
    output        irq_pending,
    output [31:0] irq_cause,
    input         retire,
    // PMP
    output [31:0]  pmpcfg_o,
    output [127:0] pmpaddr_o
);
    reg [1:0]  priv;
    reg        mie_g, mpie, mpp;                 // mpp: 1 = M, 0 = U
    reg        msie, mtie, meie;
    reg [31:0] mtvec, mscratch, mepc, mcause, mtval;
    reg [2:0]  mcounteren;
    reg [63:0] mcycle, minstret;
    reg [7:0]  pcfg [0:3];
    reg [31:0] paddr [0:3];

    assign priv_o  = priv;
    assign mtvec_o = mtvec;
    assign mepc_o  = mepc;
    assign pmpcfg_o  = {pcfg[3], pcfg[2], pcfg[1], pcfg[0]};
    assign pmpaddr_o = {paddr[3], paddr[2], paddr[1], paddr[0]};

    // ---- interrupts: priority MEI > MSI > MTI; U-mode always takes enabled M interrupts
    wire [2:0] pend = {ext_irq & meie, soft_irq & msie, timer_irq & mtie};
    wire       en   = (priv == 2'b00) | mie_g;
    assign irq_pending = en & (|pend);
    assign irq_cause   = pend[2] ? 32'h8000_000B : pend[1] ? 32'h8000_0003 : 32'h8000_0007;

    // ---- read
    reg known;
    always @* begin
        known = 1'b1; rdata = 32'b0;
        case (addr)
            12'h300: rdata = {19'b0, mpp, mpp, 3'b0, mpie, 3'b0, mie_g, 3'b0};        // mstatus
            12'h301: rdata = 32'h4010_1101;                                           // misa: RV32 IMA + U
            12'h304: rdata = {20'b0, meie, 3'b0, mtie, 3'b0, msie, 3'b0};             // mie
            12'h305: rdata = mtvec;
            12'h306: rdata = {29'b0, mcounteren};
            12'h340: rdata = mscratch;
            12'h341: rdata = mepc;
            12'h342: rdata = mcause;
            12'h343: rdata = mtval;
            12'h344: rdata = {20'b0, ext_irq, 3'b0, timer_irq, 3'b0, soft_irq, 3'b0}; // mip
            12'h3A0: rdata = pmpcfg_o;
            12'h3B0: rdata = paddr[0];
            12'h3B1: rdata = paddr[1];
            12'h3B2: rdata = paddr[2];
            12'h3B3: rdata = paddr[3];
            12'hB00, 12'hC00: rdata = mcycle[31:0];
            12'hB80, 12'hC80: rdata = mcycle[63:32];
            12'hB02, 12'hC02: rdata = minstret[31:0];
            12'hB82, 12'hC82: rdata = minstret[63:32];
            12'hC01: rdata = mtime_i[31:0];
            12'hC81: rdata = mtime_i[63:32];
            12'hF11, 12'hF12, 12'hF13, 12'hF14: rdata = 32'b0;
            default: known = 1'b0;
        endcase
    end

    // ---- access checks: privilege level, read-only space, user counter enables
    wire [1:0] need   = addr[9:8];
    wire       is_cnt = (addr[11:4] == 8'hC0) | (addr[11:4] == 8'hC8);        // cycle/time/instret (+h)
    wire       cntbit = (addr[3:0] == 4'h0) ? mcounteren[0] : (addr[3:0] == 4'h1) ? mcounteren[1] : mcounteren[2];
    wire       priv_ok = is_cnt ? ((priv == 2'b11) | cntbit) : (priv >= need);
    wire       read_only = (addr[11:10] == 2'b11);
    assign illegal = csr_en && (!known || !priv_ok || (do_write && read_only));

    reg [31:0] nv;
    always @* begin
        case (op)
            2'b01:   nv = wdata;
            2'b10:   nv = rdata | wdata;
            default: nv = rdata & ~wdata;
        endcase
    end
    wire wr = commit && csr_en && do_write && !illegal;

    // PMP write protection (locked entries; TOR-locked neighbour protects the lower address)
    function pa_locked(input integer i);
        pa_locked = pcfg[i][7] | ((i < 3) ? (pcfg[i+1][7] & (pcfg[i+1][4:3] == 2'b01)) : 1'b0);
    endfunction

    integer k;
    reg [7:0] nb;
    always @(posedge clk) begin
        if (rst) begin
            priv <= 2'b11; mie_g <= 0; mpie <= 0; mpp <= 1; msie <= 0; mtie <= 0; meie <= 0;
            mtvec <= 0; mscratch <= 0; mepc <= 0; mcause <= 0; mtval <= 0; mcounteren <= 0;
            mcycle <= 0; minstret <= 0;
            for (k = 0; k < 4; k = k + 1) begin pcfg[k] <= 8'b0; paddr[k] <= 32'b0; end
        end else begin
            mcycle <= mcycle + 64'd1;
            if (retire) minstret <= minstret + 64'd1;
            if (trap_enter) begin
                mepc <= trap_epc; mcause <= trap_cause; mtval <= trap_val;
                mpie <= mie_g; mie_g <= 1'b0; mpp <= (priv == 2'b11); priv <= 2'b11;
            end else if (mret_commit) begin
                priv <= mpp ? 2'b11 : 2'b00; mie_g <= mpie; mpie <= 1'b1; mpp <= 1'b0;
            end else if (wr) begin
                case (addr)
                    12'h300: begin
                        mie_g <= nv[3]; mpie <= nv[7];
                        if (nv[12:11] == 2'b11) mpp <= 1'b1; else if (nv[12:11] == 2'b00) mpp <= 1'b0;
                    end
                    12'h304: begin msie <= nv[3]; mtie <= nv[7]; meie <= nv[11]; end
                    12'h305: mtvec <= {nv[31:2], 1'b0, nv[0]};     // direct (0) or vectored (1)
                    12'h306: mcounteren <= nv[2:0];
                    12'h340: mscratch <= nv;
                    12'h341: mepc <= {nv[31:2], 2'b00};
                    12'h342: mcause <= nv;
                    12'h343: mtval <= nv;
                    12'h3A0: for (k = 0; k < 4; k = k + 1) begin
                                 nb = nv[8*k +: 8] & 8'h9F;                      // reserved bits read as 0
                                 if (!pcfg[k][7] && !(nb[1] && !nb[0])) pcfg[k] <= nb;   // W without R is reserved
                             end
                    12'h3B0: if (!pa_locked(0)) paddr[0] <= nv;
                    12'h3B1: if (!pa_locked(1)) paddr[1] <= nv;
                    12'h3B2: if (!pa_locked(2)) paddr[2] <= nv;
                    12'h3B3: if (!pa_locked(3)) paddr[3] <= nv;
                    12'hB00: mcycle[31:0]    <= nv;
                    12'hB80: mcycle[63:32]   <= nv;
                    12'hB02: minstret[31:0]  <= nv;
                    12'hB82: minstret[63:32] <= nv;
                    default: ;                                       // WARL: misa, mip, ... ignored
                endcase
            end
        end
    end
endmodule
