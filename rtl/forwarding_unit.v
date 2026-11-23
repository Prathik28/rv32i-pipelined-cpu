// Data-hazard forwarding (EX stage operands)
//   2'b00 : value read from regfile in ID (ID/EX register)
//   2'b10 : forward from EX/MEM (ALU result of previous instruction)
//   2'b01 : forward from MEM/WB (write-back data, incl. load data)
module forwarding_unit (
    input  [4:0] idex_rs1,
    input  [4:0] idex_rs2,
    input  [4:0] exmem_rd,
    input        exmem_reg_write,
    input  [4:0] memwb_rd,
    input        memwb_reg_write,
    output reg [1:0] fwd_a,
    output reg [1:0] fwd_b
);
    always @* begin
        // EX/MEM has priority: it holds the most recent value.
        if (exmem_reg_write && exmem_rd != 0 && exmem_rd == idex_rs1)      fwd_a = 2'b10;
        else if (memwb_reg_write && memwb_rd != 0 && memwb_rd == idex_rs1) fwd_a = 2'b01;
        else                                                               fwd_a = 2'b00;

        if (exmem_reg_write && exmem_rd != 0 && exmem_rd == idex_rs2)      fwd_b = 2'b10;
        else if (memwb_reg_write && memwb_rd != 0 && memwb_rd == idex_rs2) fwd_b = 2'b01;
        else                                                               fwd_b = 2'b00;
    end
endmodule
