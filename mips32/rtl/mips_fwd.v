// EX-stage forwarding: 2'b10 from EX/MEM, 2'b01 from MEM/WB, 2'b00 from the ID/EX register
module mips_fwd (
    input  [4:0] idex_rs, idex_rt,
    input  [4:0] exmem_dest, memwb_dest,
    input        exmem_reg_write, memwb_reg_write,
    output reg [1:0] fwd_a, fwd_b
);
    always @* begin
        if (exmem_reg_write && exmem_dest != 0 && exmem_dest == idex_rs)      fwd_a = 2'b10;
        else if (memwb_reg_write && memwb_dest != 0 && memwb_dest == idex_rs) fwd_a = 2'b01;
        else                                                                  fwd_a = 2'b00;
        if (exmem_reg_write && exmem_dest != 0 && exmem_dest == idex_rt)      fwd_b = 2'b10;
        else if (memwb_reg_write && memwb_dest != 0 && memwb_dest == idex_rt) fwd_b = 2'b01;
        else                                                                  fwd_b = 2'b00;
    end
endmodule
