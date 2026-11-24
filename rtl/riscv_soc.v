// SoC: core + instruction RAM + data RAM + slow RAM (wait states) + MMIO block.
//
//   0x0000_0000 .. 0x0000_0FFF   data RAM (4 KiB)
//   0x2000_0000 .. 0x2000_0FFF   slow RAM (4 KiB, WAITCFG extra wait cycles per access)
//   0x3000_0000 .. 0x3000_0FFF   instruction RAM through the data bus (self-modifying code; use FENCE.I)
//   0x1000_0000  HALT      (W)   write ends the program; value = exit code
//   0x1000_0004  PUTCHAR   (W)   prints a character in simulation
//   0x1000_0008  MTIMECMP  (RW)  low word   (reset all-ones => no timer interrupt)
//   0x1000_000C  MTIME     (R)   low word of the free-running 64-bit cycle counter
//   0x1000_0010  LEDS      (RW)  GPIO output (FPGA LEDs)
//   0x1000_0014  WAITCFG   (RW)  extra wait cycles of the slow RAM (0..15)
//   0x1000_0018  MSIP      (RW)  bit0 = machine software interrupt pending
//   0x1000_001C  EXTIRQ    (RW)  bit0 = software-driven external interrupt line (OR'd with the pin)
//   0x1000_0020  MTIMECMPH (RW)  high word
//   0x1000_0024  MTIMEH    (R)   high word
// Any address outside these regions raises an access fault in the core.
module riscv_soc #(parameter INIT_FILE = "", parameter BTB_ENTRIES = 16) (
    input         clk,
    input         rst,
    input         ext_irq,
    output        halt,
    output [31:0] exit_code,
    output [15:0] leds
);
    wire [31:0] imem_addr, imem_rdata;
    wire        d_req, d_we, d_ready;
    wire [31:0] d_addr, d_wdata, d_rdata;
    wire [3:0]  d_be;

    // ---- address decode (word aligned bus address) ----
    wire sel_ram  = (d_addr[31:12] == 20'h00000);
    wire sel_slow = (d_addr[31:12] == 20'h20000);
    wire sel_iram = (d_addr[31:12] == 20'h30000);
    wire sel_mmio = (d_addr[31:8]  == 24'h100000);
    wire [5:0] reg_sel = d_addr[7:2];

    // ---- slow RAM wait-state generator ----
    reg [3:0] waitcfg, wcnt;
    reg       wbusy;
    wire      slow_acc   = d_req & sel_slow;
    wire      slow_ready = (waitcfg == 4'd0) | (wbusy & (wcnt == 4'd0));
    assign    d_ready    = slow_acc ? slow_ready : 1'b1;
    always @(posedge clk) begin
        if (rst) begin wbusy <= 0; wcnt <= 0; end
        else if (slow_acc && !slow_ready) begin
            if (!wbusy) begin wbusy <= 1; wcnt <= waitcfg - 4'd1; end
            else        wcnt <= wcnt - 4'd1;
        end else if (slow_acc && slow_ready) wbusy <= 0;
    end

    // ---- RAMs ----
    wire [31:0] ram_rdata, slow_rdata, iram_rdata;
    dmem u_ram  (.clk(clk), .we(d_req & d_we & sel_ram),               .be(d_be), .addr(d_addr),
                 .wdata(d_wdata), .rdata(ram_rdata));
    dmem u_slow (.clk(clk), .we(d_req & d_we & sel_slow & slow_ready), .be(d_be), .addr(d_addr),
                 .wdata(d_wdata), .rdata(slow_rdata));
    imem #(.INIT_FILE(INIT_FILE)) u_imem (
        .clk(clk), .addr(imem_addr), .rdata(imem_rdata),
        .d_we(d_req & d_we & sel_iram), .d_be(d_be), .d_addr(d_addr),
        .d_wdata(d_wdata), .d_rdata(iram_rdata));

    // ---- MMIO ----
    wire       mmio_w = d_req & d_we & sel_mmio;
    wire [1:0] lane   = d_be[0] ? 2'd0 : d_be[1] ? 2'd1 : d_be[2] ? 2'd2 : 2'd3;
    wire [31:0] mw    = d_wdata >> {lane, 3'b000};

    reg [63:0] mtime, mtimecmp;
    reg [15:0] led_r;
    reg        msip_r, extirq_r;
    reg [31:0] mmio_rdata;

    assign halt      = mmio_w & (reg_sel == 6'd0);
    reg [31:0] exit_r;
    assign exit_code = exit_r;           // latched at the halt write (stable after the edge)
    always @(posedge clk) if (rst) exit_r <= 32'b0; else if (halt) exit_r <= mw;
    assign leds      = led_r;

    always @(posedge clk) begin
        if (rst) begin
            mtime <= 0; mtimecmp <= {64{1'b1}}; led_r <= 0; waitcfg <= 0; msip_r <= 0; extirq_r <= 0;
        end else begin
            mtime <= mtime + 64'd1;
            if (mmio_w) case (reg_sel)
                6'd2:  mtimecmp[31:0]  <= mw;
                6'd4:  led_r           <= mw[15:0];
                6'd5:  waitcfg         <= mw[3:0];
                6'd6:  msip_r          <= mw[0];
                6'd7:  extirq_r        <= mw[0];
                6'd8:  mtimecmp[63:32] <= mw;
                default: ;
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk)
        if (mmio_w && reg_sel == 6'd1) $write("%c", mw[7:0]);
`endif

    always @* begin
        case (reg_sel)
            6'd2:    mmio_rdata = mtimecmp[31:0];
            6'd3:    mmio_rdata = mtime[31:0];
            6'd4:    mmio_rdata = {16'b0, led_r};
            6'd5:    mmio_rdata = {28'b0, waitcfg};
            6'd6:    mmio_rdata = {31'b0, msip_r};
            6'd7:    mmio_rdata = {31'b0, extirq_r};
            6'd8:    mmio_rdata = mtimecmp[63:32];
            6'd9:    mmio_rdata = mtime[63:32];
            default: mmio_rdata = 32'b0;
        endcase
    end

    assign d_rdata = sel_ram ? ram_rdata : sel_slow ? slow_rdata :
                     sel_iram ? iram_rdata : sel_mmio ? mmio_rdata : 32'b0;

    riscv_core #(.BTB_ENTRIES(BTB_ENTRIES)) u_core (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_req(d_req), .dmem_we(d_we), .dmem_addr(d_addr), .dmem_wdata(d_wdata),
        .dmem_be(d_be), .dmem_rdata(d_rdata), .dmem_ready(d_ready),
        .irq_timer(mtime >= mtimecmp), .irq_soft(msip_r), .irq_ext(ext_irq | extirq_r),
        .mtime(mtime), .stop(halt),
        .perf_cycles(), .perf_instret(), .perf_stall_lu(), .perf_stall_div(),
        .perf_flushes(), .perf_branches(), .perf_mispred(), .perf_traps(), .perf_stall_mem()
    );
endmodule
