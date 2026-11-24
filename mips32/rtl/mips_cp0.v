// Minimal MIPS32 coprocessor 0: Status, Cause, EPC, BadVAddr, Count, Compare.
//   Status  (12): IM[15:8], EXL[1], IE[0]          Cause (13): BD[31], IP[15:8], ExcCode[6:2]
//   IP0/IP1 are software interrupt requests (writable through MTC0 Cause); IP7 is the timer
//   (Count == Compare; cleared by writing Compare). Exceptions vector to 0x180.
module mips_cp0 (
    input         clk,
    input         rst,
    // MFC0 / MTC0 (EX stage)
    input  [4:0]  reg_sel,
    input         write_en,
    input  [31:0] wdata,
    output reg [31:0] rdata,
    // exception entry
    input         exc_enter,
    input  [31:0] exc_epc,
    input         exc_bd,
    input  [4:0]  exc_code,
    input         badv_we,
    input  [31:0] badv_val,
    input         eret_commit,
    output [31:0] epc_o,
    output        irq_pending
);
    reg [7:0]  im;
    reg        exl, ie, bd, ip7;
    reg [1:0]  ip_soft;
    reg [4:0]  exccode;
    reg [31:0] epc, badvaddr, count, compare;

    assign epc_o = epc;
    wire [7:0] ip = {ip7, 5'b0, ip_soft};
    assign irq_pending = ie & ~exl & (|(ip & im));

    always @* begin
        case (reg_sel)
            5'd8:    rdata = badvaddr;
            5'd9:    rdata = count;
            5'd11:   rdata = compare;
            5'd12:   rdata = {16'b0, im, 6'b0, exl, ie};
            5'd13:   rdata = {bd, 15'b0, ip, 1'b0, exccode, 2'b0};
            5'd14:   rdata = epc;
            default: rdata = 32'b0;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            im <= 0; exl <= 0; ie <= 0; bd <= 0; ip7 <= 0; ip_soft <= 0; exccode <= 0;
            epc <= 0; badvaddr <= 0; count <= 0; compare <= 32'hFFFF_FFFF;
        end else begin
            count <= count + 32'd1;
            if (count == compare) ip7 <= 1'b1;
            if (exc_enter) begin
                if (!exl) begin epc <= exc_epc; bd <= exc_bd; end   // not updated while EXL is already set
                exl <= 1'b1; exccode <= exc_code;
                if (badv_we) badvaddr <= badv_val;
            end else if (eret_commit) begin
                exl <= 1'b0;
            end else if (write_en) begin
                case (reg_sel)
                    5'd9:  count <= wdata;
                    5'd11: begin compare <= wdata; ip7 <= 1'b0; end
                    5'd12: begin im <= wdata[15:8]; exl <= wdata[1]; ie <= wdata[0]; end
                    5'd13: ip_soft <= wdata[9:8];
                    5'd14: epc <= wdata;
                    default: ;
                endcase
            end
        end
    end
endmodule
